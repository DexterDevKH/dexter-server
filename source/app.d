import core.time;
import std.algorithm.searching;
import std.array;
import std.conv;
import std.format;
import std.getopt;
import std.json;
import process = std.process;
import std.string;
import std.uuid;

import vibe.core.core;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.http.websockets;
import vibe.inet.url;
import vibe.stream.operations : readAllUTF8;
import vibe.stream.tls;
import vibe.web.web;

import slf4d;
import slf4d: Logger;
import slf4d.default_provider;

import provision : provisionVersion;

enum brandingCode = format!"anisette-v3-server (dexter macOS proxy v%s)"(provisionVersion);
enum fallbackClientInfo = "<MacBookPro13,3> <Mac OS X;10.12.6;16G29> <com.apple.AuthKit/1 (com.apple.akd/1.0)>";
enum fallbackUserAgent = "akd/1.0 CFNetwork/811.5.4 Darwin/16.7.0";

__gshared string[] upstreamServers;
__gshared Duration timeout;

struct UpstreamResponse {
	int statusCode;
	string contentType;
	string responseBody;
}

UpstreamResponse forwardGET(string path) {
	auto log = getLogger();
	auto settings = new HTTPClientSettings;
	settings.connectTimeout = 5.seconds;
	settings.readTimeout = timeout;

	foreach (upstream; upstreamServers) {
		try {
			UpstreamResponse res;
			auto targetUrl = URL(upstream ~ path);
			log.infoF!"[->] Forwarding GET %s to %s"(path, targetUrl.toString());

			requestHTTP(targetUrl,
				(scope req) {
					req.method = HTTPMethod.GET;
					req.headers["User-Agent"] = "dexter-server-proxy";
					req.headers["Accept"] = "application/json";
				},
				(scope upstreamRes) {
					res.statusCode = upstreamRes.statusCode;
					if ("Content-Type" in upstreamRes.headers) {
						res.contentType = upstreamRes.headers["Content-Type"];
					}
					res.responseBody = upstreamRes.bodyReader.readAllUTF8();
				},
				settings
			);

			if (res.statusCode == 200) {
				log.infoF!"[<-] Upstream %s responded with 200 OK for GET %s"(upstream, path);
				return res;
			} else {
				log.warnF!"[!] Upstream %s returned HTTP %d for GET %s"(upstream, res.statusCode, path);
			}
		} catch (Exception ex) {
			log.warnF!"[!] Failed GET %s on upstream %s: %s"(path, upstream, ex.msg);
		}
	}
	throw new Exception("All upstream servers failed for GET " ~ path);
}

UpstreamResponse forwardPOST(string path, string jsonPayload) {
	auto log = getLogger();
	auto settings = new HTTPClientSettings;
	settings.connectTimeout = 5.seconds;
	settings.readTimeout = timeout;

	foreach (upstream; upstreamServers) {
		try {
			UpstreamResponse res;
			auto targetUrl = URL(upstream ~ path);
			log.infoF!"[->] Forwarding POST %s to %s"(path, targetUrl.toString());

			requestHTTP(targetUrl,
				(scope req) {
					req.method = HTTPMethod.POST;
					req.headers["User-Agent"] = "dexter-server-proxy";
					req.headers["Content-Type"] = "application/json";
					req.headers["Accept"] = "application/json";
					req.headers["Content-Length"] = to!string(jsonPayload.length);
					req.bodyWriter.write(cast(const(ubyte)[]) jsonPayload);
				},
				(scope upstreamRes) {
					res.statusCode = upstreamRes.statusCode;
					if ("Content-Type" in upstreamRes.headers) {
						res.contentType = upstreamRes.headers["Content-Type"];
					}
					res.responseBody = upstreamRes.bodyReader.readAllUTF8();
				},
				settings
			);

			if (res.statusCode == 200) {
				log.infoF!"[<-] Upstream %s responded with 200 OK for POST %s"(upstream, path);
				return res;
			} else {
				log.warnF!"[!] Upstream %s returned HTTP %d for POST %s: %s"(upstream, res.statusCode, path, res.responseBody);
			}
		} catch (Exception ex) {
			log.warnF!"[!] Failed POST %s on upstream %s: %s"(path, upstream, ex.msg);
		}
	}
	throw new Exception("All upstream servers failed for POST " ~ path);
}

int main(string[] args) {
	debug {
		configureLoggingProvider(new shared DefaultProvider(true, Levels.DEBUG));
	} else {
		configureLoggingProvider(new shared DefaultProvider(true, Levels.INFO));
	}

	Logger log = getLogger();
	log.info(brandingCode);
	log.info("Starting dexter-server as macOS ADI Reverse Proxy...");

	string hostname = "0.0.0.0";
	ushort port = 6969;

	string configurationPath = null;
	string certificateChainPath = null;
	string privateKeyPath = null;

	long timeoutMsecs = 15000;
	bool skipServerStartup = false;
	string customUpstream = null;

	auto helpInformation = getopt(
		args,
		"n|host", format!"The hostname to bind to (default: %s)"(hostname), &hostname,
		"p|port", format!"The port to bind to (default: %s)"(port), &port,
		"u|upstream", "Comma-separated list of upstream macOS ADI server URLs (e.g. https://new.ani.sidestore.io)", &customUpstream,
		"a|adi-path", "Legacy argument (unused in reverse proxy mode)", &configurationPath,
		"timeout", format!"Timeout duration in milliseconds (default: %d)"(timeoutMsecs), &timeoutMsecs,
		"private-key", "Path to the PEM-formatted private key file for HTTPS support (requires --cert-chain)", &certificateChainPath,
		"cert-chain", "Path to the PEM-formatted certificate chain file for HTTPS support (requires --private-key)", &privateKeyPath,
		"skip-server-startup", "If provided the server will skip HTTP binding and exit immediately.", &skipServerStartup,
	);

	timeout = dur!"msecs"(timeoutMsecs);

	if ((certificateChainPath && !privateKeyPath) || (!certificateChainPath && privateKeyPath)) {
		log.error("--certificate-chain and --private-key must both be specified for HTTPS support (they can both be in the same file though).");
		return 1;
	}

	if (helpInformation.helpWanted) {
		defaultGetoptPrinter("anisette-server with v3 reverse-proxy support", helpInformation.options);
		return 0;
	}

	if (skipServerStartup) {
		log.info("skipServerStartup flag provided, exiting.");
		return 0;
	}

	// Build upstream servers list
	string envUpstream = process.environment.get("UPSTREAM_ANISETTE_URL", process.environment.get("UPSTREAM_SERVERS", null));
	if (customUpstream.length == 0 && envUpstream.length > 0) {
		customUpstream = envUpstream;
	}

	if (customUpstream.length > 0) {
		foreach (entry; customUpstream.split(",")) {
			auto trimmed = entry.strip();
			if (trimmed.length > 0) {
				if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
					trimmed = "https://" ~ trimmed;
				}
				if (trimmed.endsWith("/")) {
					trimmed = trimmed[0 .. $ - 1];
				}
				upstreamServers ~= trimmed;
			}
		}
	}

	// Default verified macOS ADI upstreams
	string[] defaultUpstreams = [
		"https://new.ani.sidestore.io",
		"https://mac-ani.jkcoxson.com",
		"https://ani.iloader.app",
		"https://ani3.stikstore.app",
		"https://ani.jkcoxson.com",
		"https://ani2.stikstore.app"
	];

	foreach (def; defaultUpstreams) {
		if (!upstreamServers.canFind(def)) {
			upstreamServers ~= def;
		}
	}

	log.info("Configured Upstream macOS ADI Servers (in failover order):");
	foreach (idx, s; upstreamServers) {
		log.infoF!"  [%d] %s"(idx + 1, s);
	}

	// Create router and register web interface
	auto router = new URLRouter();
	router.registerWebInterface(new AnisetteService());

	// Start up the HTTP server
	auto settings = new HTTPServerSettings;
	settings.port = port;
	settings.bindAddresses = [hostname];
	settings.sessionStore = new MemorySessionStore;
	if (certificateChainPath) {
		settings.tlsContext = createTLSContext(TLSContextKind.server);
		settings.tlsContext.useCertificateChainFile(certificateChainPath);
		settings.tlsContext.usePrivateKeyFile(privateKeyPath);
	}

	auto listener = listenHTTP(settings, router);
	log.infoF!"Server listening on %s:%d"(hostname, port);

	return runApplication(&args);
}

class AnisetteService {
	@method(HTTPMethod.GET)
	@path("/")
	void handleV1Request(HTTPServerRequest req, HTTPServerResponse res) {
		auto log = getLogger();
		log.info("[<<] anisette-v1 request (proxying to upstream)");

		try {
			auto upstreamRes = forwardGET("/");
			res.headers["Implementation-Version"] = brandingCode;
			res.writeBody(upstreamRes.responseBody, upstreamRes.contentType.length ? upstreamRes.contentType : "application/json");
			log.info("[>>] 200 OK (v1 relayed from upstream)");
		} catch (Exception ex) {
			log.errorF!"[!!] Failed to relay v1 request: %s"(ex.msg);
			res.statusCode = 502;
			res.writeBody(format!`{"error": "Upstream error: %s"}`(ex.msg), "application/json");
		}
	}

	@method(HTTPMethod.GET)
	@path("/v3/client_info")
	void getClientInfo(HTTPServerRequest req, HTTPServerResponse res) {
		auto log = getLogger();
		log.info("[<<] anisette-v3 /v3/client_info (proxying to upstream)");

		try {
			auto upstreamRes = forwardGET("/v3/client_info");
			res.headers["Implementation-Version"] = brandingCode;
			res.writeBody(upstreamRes.responseBody, upstreamRes.contentType.length ? upstreamRes.contentType : "application/json");
			log.info("[>>] 200 OK (client_info relayed)");
		} catch (Exception ex) {
			log.warnF!"[!] Upstream client_info failed: %s, returning fallback macOS client info"(ex.msg);
			JSONValue fallbackJson = [
				"client_info": fallbackClientInfo,
				"user_agent": fallbackUserAgent
			];
			res.headers["Implementation-Version"] = brandingCode;
			res.writeBody(fallbackJson.toString(JSONOptions.doNotEscapeSlashes), "application/json");
		}
	}

	@method(HTTPMethod.POST)
	@path("/v3/get_headers")
	void getHeaders(HTTPServerRequest req, HTTPServerResponse res) {
		auto log = getLogger();
		log.info("[<<] anisette-v3 /v3/get_headers (proxying to upstream)");

		string requestPayload;
		try {
			requestPayload = req.bodyReader.readAllUTF8();
		} catch (Exception ex) {
			log.errorF!"[!] Error reading request body: %s"(ex.msg);
			JSONValue error = [
				"result": "GetHeadersError",
				"message": "Failed to read request body: " ~ ex.msg
			];
			res.headers["Implementation-Version"] = brandingCode;
			res.writeBody(error.toString(JSONOptions.doNotEscapeSlashes), "application/json");
			return;
		}

		try {
			auto upstreamRes = forwardPOST("/v3/get_headers", requestPayload);
			res.headers["Implementation-Version"] = brandingCode;
			res.writeBody(upstreamRes.responseBody, upstreamRes.contentType.length ? upstreamRes.contentType : "application/json");
			log.info("[>>] anisette-v3 /v3/get_headers OK (relayed from upstream)");
		} catch (Exception ex) {
			log.errorF!"[!] Failed to forward get_headers to upstream: %s"(ex.msg);
			JSONValue error = [
				"result": "GetHeadersError",
				"message": "Upstream error: " ~ ex.msg
			];
			res.headers["Implementation-Version"] = brandingCode;
			res.writeBody(error.toString(JSONOptions.doNotEscapeSlashes), "application/json");
		}
	}

	@method(HTTPMethod.GET)
	@path("/v3/provisioning_session")
	void provisionSession(scope WebSocket clientSocket) {
		auto log = getLogger();
		scope(exit) {
			if (clientSocket.connected) {
				clientSocket.close();
			}
		}

		auto requestUUID = randomUUID().toString();
		log.infoF!"[<< %s] anisette-v3 /v3/provisioning_session client connected"(requestUUID);

		bool relayed = false;

		foreach (upstream; upstreamServers) {
			if (!clientSocket.connected) {
				log.infoF!"[-- %s] Client disconnected before upstream connection"(requestUUID);
				return;
			}

			bool sessionStarted = false;
			try {
				log.infoF!"[.. %s] Connecting to upstream WebSocket: %s"(requestUUID, upstream);
				auto wsUrl = URL(upstream ~ "/v3/provisioning_session");
				if (wsUrl.schema == "https" || wsUrl.schema == "wss") {
					wsUrl.schema = "wss";
				} else {
					wsUrl.schema = "ws";
				}

				auto settings = new HTTPClientSettings;
				settings.connectTimeout = 5.seconds;
				settings.readTimeout = timeout;

				WebSocket upstreamWs = connectWebSocket(wsUrl, settings);
				scope(exit) {
					if (upstreamWs !is null && upstreamWs.connected) {
						upstreamWs.close();
					}
				}

				log.infoF!"[== %s] Connected to upstream WebSocket at %s"(requestUUID, upstream);
				bool upstreamTurn = true;

				while (clientSocket.connected && upstreamWs.connected) {
					if (upstreamTurn) {
						if (!upstreamWs.waitForData(timeout)) {
							log.warnF!"[-- %s] Timeout waiting for data from upstream"(requestUUID);
							break;
						}
						string msg = upstreamWs.receiveText();
						log.infoF!"[>> %s] [Upstream -> Client] %s"(requestUUID, msg);
						clientSocket.send(msg);
						sessionStarted = true;

						if (msg.canFind("ProvisioningSuccess") || msg.canFind("Error") || msg.canFind("Invalid")) {
							log.infoF!"[== %s] Upstream concluded session with: %s"(
								requestUUID,
								msg.canFind("ProvisioningSuccess") ? "SUCCESS" : "TERMINATION"
							);
							if (msg.canFind("ProvisioningSuccess")) {
								sleep(500.msecs);
							}
							break;
						}
						upstreamTurn = false;
					} else {
						if (!clientSocket.waitForData(timeout)) {
							log.warnF!"[-- %s] Timeout waiting for data from client"(requestUUID);
							break;
						}
						string msg = clientSocket.receiveText();
						log.infoF!"[<< %s] [Client -> Upstream] %s"(requestUUID, msg);
						upstreamWs.send(msg);
						upstreamTurn = true;
					}
				}

				relayed = true;
				log.infoF!"[== %s] Provisioning session finished via upstream %s"(requestUUID, upstream);
				break;
			} catch (Exception ex) {
				log.warnF!"[!! %s] Upstream %s failed: %s"(requestUUID, upstream, ex.msg);
				if (sessionStarted) {
					break;
				}
			}
		}

		if (!relayed && clientSocket.connected) {
			log.errorF!"[!! %s] All upstream servers failed for provisioning session"(requestUUID);
			try {
				JSONValue err = [
					"result": "StartProvisioningError",
					"message": "All upstream macOS ADI servers failed to connect"
				];
				clientSocket.send(err.toString(JSONOptions.doNotEscapeSlashes));
			} catch (Exception ex) {}
		}
	}
}
