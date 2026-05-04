#include <common/include/protocol.hpp>
#include <common/include/interpolator.hpp>
#include <common/include/logger.hpp>
#include <common/include/predictor.hpp>
#include <core/include/bot.hpp>
#include <core/include/constants.hpp>
#include <core/include/world.hpp>

#include <SDL2/SDL.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <iostream>
#include <optional>
#include <string>
#include <thread>
#include <vector>

static constexpr int WIN_W = 768;
static constexpr int WIN_H = 624;

static bool setNonBlocking(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    return flags != -1 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1;
}

static bool sendAll(int fd, const std::string& data)
{
    size_t sent = 0;
    while (sent < data.size()) {
        ssize_t n = ::send(fd, data.data() + sent, data.size() - sent, MSG_NOSIGNAL);
        if (n <= 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

// ---------------------------------------------------------------------------
// Connect to server — returns -1 on failure (non-fatal)
// ---------------------------------------------------------------------------
static int connectToServer(const char* host, uint16_t port)
{
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(port);
    if (::inet_pton(AF_INET, host, &addr.sin_addr) <= 0) { ::close(fd); return -1; }

    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        ::close(fd);
        return -1;
    }

    setNonBlocking(fd);
    {
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }
    return fd;
}

// ---------------------------------------------------------------------------
// Rendering helpers
// ---------------------------------------------------------------------------
static inline int worldToScreen(float v, int dim) { return static_cast<int>(v * dim); }

static void drawPlane(SDL_Renderer* r, const PlaneSnapshot& p, bool isMe)
{
    if (p.isDead && !p.hasJumped) return;

    // Plane body
    if (!p.isDead) {
        SDL_SetRenderDrawColor(r,
            isMe ? 80 : 220,
            isMe ? 120 : 80,
            isMe ? 220 : 80, 255);

        const int px = worldToScreen(p.x, WIN_W);
        const int py = worldToScreen(p.y, WIN_H);
        SDL_Rect rect{ px - 12, py - 6, 24, 12 };
        SDL_RenderFillRect(r, &rect);

        // Direction indicator
        SDL_SetRenderDrawColor(r, 255, 255, 0, 255);
        const float rad = p.dir * static_cast<float>(M_PI) / 180.f;
        SDL_RenderDrawLine(r, px, py,
            px + static_cast<int>(14 * std::sin(rad)),
            py - static_cast<int>(14 * std::cos(rad)));
    }

    // Pilot
    const auto& pilot = p.pilot;
    if (p.hasJumped) {
        const int pilx = worldToScreen(pilot.x, WIN_W);
        const int pily = worldToScreen(pilot.y, WIN_H);

        if (!pilot.isDead) {
            // Chute
            if (pilot.isChuteOpen) {
                if (pilot.isChuteBroken)
                    SDL_SetRenderDrawColor(r, 200, 60, 60, 200);
                else
                    SDL_SetRenderDrawColor(r, 200, 200, 200, 220);
                SDL_Rect chuteRect{ pilx - 10, pily - 22, 20, 16 };
                SDL_RenderFillRect(r, &chuteRect);
                SDL_SetRenderDrawColor(r, 180, 180, 180, 255);
                SDL_RenderDrawLine(r, pilx - 8, pily - 6, pilx - 8, pily - 4);
                SDL_RenderDrawLine(r, pilx + 8, pily - 6, pilx + 8, pily - 4);
            }
            // Pilot body
            SDL_SetRenderDrawColor(r, 255, 180, 100, 255);
            SDL_Rect pilRect{ pilx - 4, pily - 4, 8, 8 };
            SDL_RenderFillRect(r, &pilRect);
        } else {
            // Angel — white cross
            SDL_SetRenderDrawColor(r, 255, 255, 255, 160);
            SDL_Rect angH{ pilx - 8, pily - 2, 16,  4 };
            SDL_Rect angV{ pilx - 2, pily - 8,  4, 16 };
            SDL_RenderFillRect(r, &angH);
            SDL_RenderFillRect(r, &angV);
        }
    }
}

static void drawBullet(SDL_Renderer* r, const BulletSnapshot& b)
{
    SDL_SetRenderDrawColor(r, 255, 255, 60, 255);
    const int bx = worldToScreen(b.x, WIN_W);
    const int by = worldToScreen(b.y, WIN_H);
    SDL_Rect rect{ bx - 2, by - 2, 4, 4 };
    SDL_RenderFillRect(r, &rect);
}

static void drawHUD(SDL_Renderer* r, const GameSnapshot& gs, int playerId, bool offline)
{
    // Blue score (player 0)
    SDL_SetRenderDrawColor(r, 80, 120, 220, 255);
    for (int i = 0; i < gs.planes[0].score && i < 10; ++i) {
        SDL_Rect sr{8 + i * 14, 8, 10, 10};
        SDL_RenderFillRect(r, &sr);
    }

    // Red score (player 1)
    SDL_SetRenderDrawColor(r, 220, 80, 80, 255);
    for (int i = 0; i < gs.planes[1].score && i < 10; ++i) {
        SDL_Rect sr{WIN_W - 18 - i * 14, 8, 10, 10};
        SDL_RenderFillRect(r, &sr);
    }

    // HP bars
    for (int p = 0; p < 2; ++p) {
        const int hp   = gs.planes[p].hp;
        const int barW = 60;
        const int x    = (p == 0) ? 8 : WIN_W - barW - 8;
        SDL_SetRenderDrawColor(r, 60, 60, 60, 255);
        SDL_Rect bg{x, 24, barW, 8};
        SDL_RenderFillRect(r, &bg);
        const int filled = (hp * barW) / 3;
        SDL_SetRenderDrawColor(r, 80, 220, 80, 255);
        SDL_Rect fg{x, 24, filled, 8};
        SDL_RenderFillRect(r, &fg);
    }

    // Offline indicator
    if (offline) {
        SDL_SetRenderDrawColor(r, 200, 160, 60, 200);
        SDL_Rect badge{WIN_W / 2 - 30, 6, 60, 14};
        SDL_RenderFillRect(r, &badge);
    }

    (void)playerId;
}

static void renderScene(SDL_Renderer* r, const GameSnapshot& gs, int playerId, bool offline)
{
    SDL_SetRenderDrawColor(r, 30, 30, 50, 255);
    SDL_RenderClear(r);

    // Ground
    SDL_SetRenderDrawColor(r, 80, 130, 60, 255);
    { SDL_Rect gr{0, WIN_H - 20, WIN_W, 20}; SDL_RenderFillRect(r, &gr); }

    // Barn
    SDL_SetRenderDrawColor(r, 140, 90, 50, 255);
    {
        const int bx = worldToScreen(0.5f - constants::barn::sizeX * 0.5f, WIN_W);
        const int by = worldToScreen(constants::barn::planeCollisionY, WIN_H);
        const int bw = worldToScreen(constants::barn::sizeX, WIN_W);
        const int bh = worldToScreen(constants::barn::sizeY, WIN_H);
        SDL_Rect barnRect{bx, by, bw, bh};
        SDL_RenderFillRect(r, &barnRect);
    }

    drawPlane(r, gs.planes[0], playerId == 0);
    drawPlane(r, gs.planes[1], playerId == 1);

    for (const auto& b : gs.bullets)
        drawBullet(r, b);

    drawHUD(r, gs, playerId, offline);

    if (gs.roundFinished) {
        SDL_SetRenderDrawColor(r, 0, 0, 0, 140);
        SDL_Rect winRect{WIN_W / 4, WIN_H / 3, WIN_W / 2, WIN_H / 4};
        SDL_RenderFillRect(r, &winRect);
    }

    SDL_RenderPresent(r);
}

// ---------------------------------------------------------------------------
// Build PlayerInput from current keyboard state
// ---------------------------------------------------------------------------
static PlayerInput buildInput(const uint8_t* keys)
{
    PlayerInput in{};
    if (keys[SDL_SCANCODE_W] || keys[SDL_SCANCODE_UP])
        in.throttle = PlaneThrottle::Increase;
    else if (keys[SDL_SCANCODE_S] || keys[SDL_SCANCODE_DOWN])
        in.throttle = PlaneThrottle::Decrease;
    else
        in.throttle = PlaneThrottle::Idle;

    if (keys[SDL_SCANCODE_A] || keys[SDL_SCANCODE_LEFT])
        in.pitch = PlanePitch::Left;
    else if (keys[SDL_SCANCODE_D] || keys[SDL_SCANCODE_RIGHT])
        in.pitch = PlanePitch::Right;
    else
        in.pitch = PlanePitch::Idle;

    in.shoot = (keys[SDL_SCANCODE_SPACE] != 0);
    in.jump  = (keys[SDL_SCANCODE_E] != 0 || keys[SDL_SCANCODE_RETURN] != 0);
    return in;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
int main(int argc, char* argv[])
{
    // Parse args: optional --bot flag, then optional host and port
    bool        forceBot = false;
    const char* host     = "127.0.0.1";
    uint16_t    port     = 55123;

    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--bot") {
            forceBot = true;
        } else if (i + 1 < argc && std::string(argv[i]) == "--host") {
            host = argv[++i];
        } else if (i + 1 < argc && std::string(argv[i]) == "--port") {
            port = static_cast<uint16_t>(std::atoi(argv[++i]));
        } else if (i == 1 && argv[i][0] != '-') {
            host = argv[i];  // positional: first non-flag arg is host
        } else if (i == 2 && argv[i][0] != '-') {
            port = static_cast<uint16_t>(std::atoi(argv[i]));
        }
    }

    int serverFd = -1;
    if (!forceBot) {
        std::cout << "[client] Connecting to " << host << ":" << port << " ...\n";
        serverFd = connectToServer(host, port);
    }

    const bool offline = forceBot || (serverFd < 0);
    if (offline && forceBot)
        std::cout << "[client] --bot flag set — starting offline mode vs bot.\n";
    else if (offline)
        std::cout << "[client] No server found — starting offline mode vs bot.\n";
    else
        std::cout << "[client] Connected.\n";

    // SDL init
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        std::cerr << "[client] SDL_Init failed: " << SDL_GetError() << "\n";
        if (serverFd >= 0) ::close(serverFd);
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow(
        offline ? "PvP Biplanes — Offline vs Bot" : "PvP Biplanes — Online",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_W, WIN_H, SDL_WINDOW_SHOWN);
    if (!window) {
        std::cerr << "[client] CreateWindow: " << SDL_GetError() << "\n";
        if (serverFd >= 0) ::close(serverFd);
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) {
        std::cerr << "[client] CreateRenderer: " << SDL_GetError() << "\n";
        if (serverFd >= 0) ::close(serverFd);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    // ── Online: wait for welcome message ────────────────────────────────────
    int playerId = -1;
    std::vector<uint8_t> netBuf{};

    if (!offline) {
        while (playerId == -1) {
            uint8_t tmp[256];
            ssize_t n = ::recv(serverFd, tmp, sizeof(tmp), 0);
            if (n > 0) netBuf.insert(netBuf.end(), tmp, tmp + n);
            auto json = tryReadMessage(netBuf);
            if (!json.empty()) {
                try {
                    auto wm = WelcomeMessage::fromJson(json);
                    playerId = wm.playerId;
                } catch (...) {}
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
        std::cout << "[client] Assigned player ID: " << playerId << "\n";
    }

    // ── Offline: local game world + bot ─────────────────────────────────────
    GameWorld localWorld{};
    BotAI     bot{ BotDifficulty::Medium };
    if (offline) {
        localWorld.startRound();
    }

    // ── Online smoothing: interpolator + predictor ───────────────────────────
    SnapshotInterpolator interp{};
    ClientPredictor      pred{playerId};

    // Render delay: 3 × snapshot interval gives jitter headroom.
    const double SNAPSHOT_INTERVAL_MS = 1000.0 / constants::snapshotRate;
    const double RENDER_DELAY_MS      = 3.0 * SNAPSHOT_INTERVAL_MS;

    // ── Client logger (online only) ──────────────────────────────────────────
    ClientLogger clientLog("./biplanes_client.log");

    using Clock    = std::chrono::steady_clock;
    using FpMillis = std::chrono::duration<double, std::milli>;
    const double TICK_MS = GameWorld::TICK_DT * 1000.0;

    std::optional<GameSnapshot> latestSnap{};
    std::optional<GameSnapshot> serverSnap{};  // raw server snapshots (delta base only)
    uint64_t localTick    = 0;
    double   accumMs      = 0.0;
    auto     startTime    = Clock::now();
    auto     lastTime     = startTime;

    auto nowMs = [&]() -> double {
        return std::chrono::duration_cast<FpMillis>(Clock::now() - startTime).count();
    };

    bool running = true;
    while (running) {
        auto now = Clock::now();
        double frameMs = std::chrono::duration_cast<FpMillis>(now - lastTime).count();
        lastTime = now;
        // Guard against spiral-of-death on big stalls
        if (frameMs > 100.0) frameMs = 100.0;

        // ── Events ──────────────────────────────────────────────────────────
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT ||
                (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_ESCAPE))
                running = false;
        }

        const uint8_t* keys = SDL_GetKeyboardState(nullptr);
        PlayerInput humanInput = buildInput(keys);

        if (offline) {
            // ── Offline: fixed-step simulation ──────────────────────────────
            accumMs += frameMs;
            while (accumMs >= TICK_MS) {
                PlayerInput inputs[2];
                inputs[0] = humanInput;
                inputs[1] = bot.think(
                    localWorld.planes[1],
                    localWorld.planes[0],
                    localWorld.bullets.instances(),
                    static_cast<float>(GameWorld::TICK_DT));

                localWorld.update(inputs);
                accumMs -= TICK_MS;
            }
            latestSnap = GameSnapshot::fromWorld(localWorld);
        } else {
            // ── Online: send input ───────────────────────────────────────────
            ++localTick;
            pred.applyInput(localTick, humanInput);
            clientLog.logInput(localTick, humanInput);

            InputMessage msg{};
            msg.tick     = localTick;
            msg.throttle = humanInput.throttle;
            msg.pitch    = humanInput.pitch;
            msg.shoot    = humanInput.shoot;
            msg.jump     = humanInput.jump;

            if (!sendAll(serverFd, frameMessage(msg.toJson()))) {
                std::cerr << "[client] Lost connection to server — switching to offline.\n";
                running = false;
                break;
            }

            // Receive all pending snapshots.
            uint8_t tmp[8192];
            while (true) {
                ssize_t n = ::recv(serverFd, tmp, sizeof(tmp), 0);
                if (n > 0) netBuf.insert(netBuf.end(), tmp, tmp + n);
                else break;
            }

            std::string json;
            std::optional<GameSnapshot> latestReceivedSnap;
            while (!(json = tryReadMessage(netBuf)).empty()) {
                try {
                    auto j = nlohmann::json::parse(json);
                    GameSnapshot snap;
                    const std::string type = j.value("type", std::string{});
                    if (type == "state") {
                        snap = GameSnapshot::fromJson(json);
                        serverSnap = snap;
                    } else if (type == "delta" && serverSnap.has_value()) {
                        snap = GameDeltaSnapshot::fromJson(json).apply(*serverSnap);
                        serverSnap = snap;
                    } else {
                        continue;
                    }
                    clientLog.logSnapshot(type, snap);

                    interp.push(snap, nowMs());
                    latestSnap = snap;
                    // Track the newest snapshot for a single post-loop reconcile.
                    if (!latestReceivedSnap || snap.tick > latestReceivedSnap->tick)
                        latestReceivedSnap = snap;
                } catch (...) {}
            }

            // Blend out visual correction from previous reconcile(s).
            pred.blendStep(frameMs);

            // Reconcile once with the newest snapshot from this recv burst.
            // Reconciling on every individual packet in a burst causes cumulative
            // prediction drift: each reconcile replays the full pending history
            // from a slightly newer server base, pushing the prediction forward.
            if (latestReceivedSnap) {
                const PlaneSnapshot prePhys = pred.physicsLocalPlane();
                pred.reconcile(*latestReceivedSnap);
                const PlaneSnapshot postPhys = pred.physicsLocalPlane();
                clientLog.logReconcile(
                    latestReceivedSnap->tick, latestReceivedSnap->lastAckedInputTick[playerId],
                    pred.historySize(),
                    prePhys.x, prePhys.y,
                    postPhys.x, postPhys.y,
                    latestReceivedSnap->planes[playerId].x, latestReceivedSnap->planes[playerId].y);
            }

            // Build render snapshot: local plane from prediction, remote from interpolator.
            if (!interp.empty()) {
                GameSnapshot render = interp.interpolated(nowMs() - RENDER_DELAY_MS);
                render.planes[playerId] = pred.localPlane();
                latestSnap = render;
            }

            // Log render state every 60 frames.
            if (latestSnap && (localTick % 60 == 0)) {
                clientLog.logRender(localTick, playerId,
                    latestSnap->planes[playerId],
                    latestSnap->planes[1 - playerId]);
            }

            // ~60 Hz cap when online
            std::this_thread::sleep_for(std::chrono::milliseconds(16));
        }

        // ── Render ───────────────────────────────────────────────────────────
        if (latestSnap)
            renderScene(renderer, *latestSnap, playerId, offline);
    }

    if (serverFd >= 0) ::close(serverFd);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
