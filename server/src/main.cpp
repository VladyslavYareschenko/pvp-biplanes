#include <core/include/world.hpp>
#include <common/include/protocol.hpp>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <iostream>
#include <optional>
#include <random>
#include <thread>
#include <vector>

static constexpr uint16_t PORT         = 55123;
static constexpr int      SNAPSHOT_DIV = 2;   // send snapshot every N ticks (120/2=60Hz)

// ---------------------------------------------------------------------------
// Network simulation config (read from environment variables at startup)
//
//   SIM_LATENCY_MS   Extra one-way delay added to every outgoing packet (ms). Default 0.
//   SIM_JITTER_MS    ± uniform random jitter applied on top of latency (ms). Default 0.
//   SIM_LOSS_PCT     Probability a packet is silently dropped (0–100). Default 0.
//
// Example (100ms RTT, ±20ms jitter, 2% loss):
//   SIM_LATENCY_MS=50 SIM_JITTER_MS=20 SIM_LOSS_PCT=2 ./biplanes_server
// ---------------------------------------------------------------------------
struct SimConfig
{
    int latencyMs {0};
    int jitterMs  {0};
    int lossPct   {0};
};

static SimConfig loadSimConfig()
{
    SimConfig cfg;
    if (const char* v = std::getenv("SIM_LATENCY_MS")) cfg.latencyMs = std::atoi(v);
    if (const char* v = std::getenv("SIM_JITTER_MS"))  cfg.jitterMs  = std::atoi(v);
    if (const char* v = std::getenv("SIM_LOSS_PCT"))   cfg.lossPct   = std::atoi(v);
    // Clamp to sane values
    cfg.latencyMs = std::max(0, std::min(cfg.latencyMs, 5000));
    cfg.jitterMs  = std::max(0, std::min(cfg.jitterMs,  2000));
    cfg.lossPct   = std::max(0, std::min(cfg.lossPct,   100));
    return cfg;
}

// ---------------------------------------------------------------------------
// Per-client outgoing delay queue
// ---------------------------------------------------------------------------
using Clock = std::chrono::steady_clock;

struct PendingPacket
{
    Clock::time_point sendAt;
    std::string       payload;
};

using SendQueue = std::deque<PendingPacket>;

// Enqueue a payload; optionally drop or delay it based on SimConfig.
// Returns false if the packet was dropped.
static bool enqueue(SendQueue& q, std::string payload,
                    const SimConfig& sim, std::mt19937& rng)
{
    // Loss
    if (sim.lossPct > 0) {
        std::uniform_int_distribution<int> pctDist(1, 100);
        if (pctDist(rng) <= sim.lossPct) return false;
    }

    int delayMs = sim.latencyMs;
    if (sim.jitterMs > 0) {
        std::uniform_int_distribution<int> jDist(-sim.jitterMs, sim.jitterMs);
        delayMs = std::max(0, delayMs + jDist(rng));
    }

    PendingPacket pkt;
    pkt.sendAt  = Clock::now() + std::chrono::milliseconds(delayMs);
    pkt.payload = std::move(payload);
    q.push_back(std::move(pkt));
    return true;
}

// Flush all packets whose sendAt has passed, sending them to fd.
// Returns false if a send fails (caller should disconnect).
static bool flushQueue(SendQueue& q, int fd)
{
    const auto now = Clock::now();
    while (!q.empty() && q.front().sendAt <= now)
    {
        const std::string& payload = q.front().payload;
        size_t sent = 0;
        while (sent < payload.size()) {
            ssize_t n = ::send(fd, payload.data() + sent,
                               payload.size() - sent, MSG_NOSIGNAL);
            if (n <= 0) return false;
            sent += static_cast<size_t>(n);
        }
        q.pop_front();
    }
    return true;
}

// ---------------------------------------------------------------------------
// Non-blocking helpers
// ---------------------------------------------------------------------------
static bool setNonBlocking(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    return flags != -1 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1;
}

static bool setNoDelay(int fd)
{
    int one = 1;
    return setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)) == 0;
}

// ---------------------------------------------------------------------------
// Client connection state
// ---------------------------------------------------------------------------
struct Client
{
    int                  fd         {-1};
    int                  playerId   {-1};
    std::vector<uint8_t> recvBuf    {};
    PlayerInput          lastInput  {};
    uint64_t             lastAckedInputTick{0};
    bool                 ready      {false};
    bool                 connected  {true};
    SendQueue            sendQueue  {};   // outgoing delay queue (for simulation)
};

// ---------------------------------------------------------------------------
// Accept one client, send WelcomeMessage
// ---------------------------------------------------------------------------
static Client acceptClient(int listenFd, int playerId)
{
    sockaddr_in addr{};
    socklen_t   len = sizeof(addr);
    int clientFd = ::accept(listenFd, reinterpret_cast<sockaddr*>(&addr), &len);
    if (clientFd < 0) {
        std::perror("accept");
        return {};
    }
    setNonBlocking(clientFd);
    setNoDelay(clientFd);

    char ipStr[INET_ADDRSTRLEN] {};
    inet_ntop(AF_INET, &addr.sin_addr, ipStr, sizeof(ipStr));
    std::cout << "[server] Player " << playerId << " connected from "
              << ipStr << ":" << ntohs(addr.sin_port) << "\n";

    // Send welcome immediately (bypasses sim queue — it's a handshake, not a game packet).
    WelcomeMessage wm; wm.playerId = playerId;
    std::string welcomePayload = frameMessage(wm.toJson());
    size_t sent = 0;
    const auto& wp = welcomePayload;
    while (sent < wp.size()) {
        ssize_t n = ::send(clientFd, wp.data() + sent, wp.size() - sent, MSG_NOSIGNAL);
        if (n <= 0) break;
        sent += static_cast<size_t>(n);
    }

    Client c;
    c.fd       = clientFd;
    c.playerId = playerId;
    c.connected= true;
    return c;
}

// ---------------------------------------------------------------------------
// Read available bytes from client into its buffer; parse and apply inputs
// ---------------------------------------------------------------------------
static void pumpClient(Client& c, uint64_t serverTick)
{
    if (!c.connected) return;

    uint8_t tmp[4096];
    while (true) {
        ssize_t n = ::recv(c.fd, tmp, sizeof(tmp), 0);
        if (n > 0) {
            c.recvBuf.insert(c.recvBuf.end(), tmp, tmp + n);
        } else if (n == 0) {
            std::cout << "[server] Player " << c.playerId << " disconnected\n";
            c.connected = false;
            return;
        } else {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            std::cerr << "[server] recv error for player " << c.playerId
                      << ": " << std::strerror(errno) << "\n";
            c.connected = false;
            return;
        }
    }

    std::string json;
    while (!(json = tryReadMessage(c.recvBuf)).empty()) {
        try {
            auto msg = InputMessage::fromJson(json);
            (void)serverTick;  // could enforce ordering here
            c.lastInput.throttle = msg.throttle;
            c.lastInput.pitch    = msg.pitch;
            c.lastInput.shoot    = msg.shoot;
            c.lastInput.jump     = msg.jump;
            c.lastInput.joystick = { msg.jsAngle, msg.jsMag, msg.jsActive };
            if (msg.tick > c.lastAckedInputTick)
                c.lastAckedInputTick = msg.tick;
            c.ready = true;
        } catch (...) {
            std::cerr << "[server] malformed input from player " << c.playerId << "\n";
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
int main()
{
    const SimConfig sim = loadSimConfig();
    if (sim.latencyMs || sim.jitterMs || sim.lossPct) {
        std::cout << "[server] Network simulation: latency=" << sim.latencyMs
                  << "ms  jitter=±" << sim.jitterMs
                  << "ms  loss=" << sim.lossPct << "%\n";
    }

    std::mt19937 rng{std::random_device{}()};

    // Create listen socket
    int listenFd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd < 0) { std::perror("socket"); return 1; }

    {
        int one = 1;
        setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    }

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(PORT);

    if (::bind(listenFd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::perror("bind"); return 1;
    }
    if (::listen(listenFd, 4) < 0) { std::perror("listen"); return 1; }

    std::cout << "[server] Listening on port " << PORT << " — waiting for 2 players...\n";

    // Wait for 2 clients synchronously
    std::array<Client, 2> clients{};
    for (int i = 0; i < 2; ++i) {
        std::cout << "[server] Waiting for player " << i << "...\n";
        clients[i] = acceptClient(listenFd, i);
        if (clients[i].fd < 0) { std::cerr << "Failed to accept\n"; return 1; }
    }

    std::cout << "[server] Both players connected — starting game!\n";

    GameWorld world{};
    world.startRound();

    using Duration  = std::chrono::duration<double>;
    const Duration TICK_DUR{GameWorld::TICK_DT};

    auto nextTick = Clock::now();
    uint64_t tickCount = 0;

    // Per-client delta compression: track the last snapshot sent to each client.
    std::array<std::optional<GameSnapshot>, 2> lastSentSnap{};

    while (true) {
        // Sleep until next tick
        auto now = Clock::now();
        if (now < nextTick)
            std::this_thread::sleep_until(nextTick);
        nextTick += std::chrono::duration_cast<Clock::duration>(TICK_DUR);
        ++tickCount;

        // Flush pending simulated-delay packets for each client
        for (auto& c : clients) {
            if (!c.connected) continue;
            if (!flushQueue(c.sendQueue, c.fd)) {
                std::cerr << "[server] send failed (flush) for player " << c.playerId << "\n";
                c.connected = false;
            }
        }

        // Read inputs from both clients
        for (auto& c : clients)
            pumpClient(c, tickCount);

        // Collect inputs
        PlayerInput inputs[2];
        for (int i = 0; i < 2; ++i) {
            if (clients[i].connected)
                inputs[i] = clients[i].lastInput;
        }

        // Advance world
        world.update(inputs);

        // Enqueue snapshot at reduced rate
        if (tickCount % SNAPSHOT_DIV == 0) {
            GameSnapshot snap = GameSnapshot::fromWorld(world);
            snap.lastAckedInputTick[0] = clients[0].lastAckedInputTick;
            snap.lastAckedInputTick[1] = clients[1].lastAckedInputTick;

            for (int i = 0; i < 2; ++i) {
                auto& c = clients[i];
                if (!c.connected) continue;

                std::string payload;
                if (!lastSentSnap[i].has_value()) {
                    payload = frameMessage(snap.toJson());
                } else {
                    auto delta = GameDeltaSnapshot::compute(*lastSentSnap[i], snap);
                    if (delta.has_value())
                        payload = frameMessage(delta->toJson());
                }

                if (!payload.empty()) {
                    enqueue(c.sendQueue, std::move(payload), sim, rng);
                    lastSentSnap[i] = snap;
                }
            }
        }

        // If all disconnected, reset
        bool anyConnected = false;
        for (const auto& c : clients)
            if (c.connected) anyConnected = true;

        if (!anyConnected) {
            std::cout << "[server] All players disconnected. Waiting for new game...\n";
            break;
        }
    }

    for (auto& c : clients)
        if (c.fd >= 0) ::close(c.fd);
    ::close(listenFd);
    return 0;
}
