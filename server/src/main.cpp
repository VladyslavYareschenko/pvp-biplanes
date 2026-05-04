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
#include <cstring>
#include <iostream>
#include <optional>
#include <thread>
#include <vector>

static constexpr uint16_t PORT         = 55123;
static constexpr int      SNAPSHOT_DIV = 2;   // send snapshot every N ticks (120/2=60Hz)

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
    uint64_t             lastAckedInputTick{0};  // most recent InputMessage::tick received
    bool                 ready      {false};   // received at least one input
    bool                 connected  {true};
};

// ---------------------------------------------------------------------------
// Send all bytes (blocking loop)
// ---------------------------------------------------------------------------
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

    // Send welcome
    WelcomeMessage wm; wm.playerId = playerId;
    sendAll(clientFd, frameMessage(wm.toJson()));

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

    using Clock     = std::chrono::steady_clock;
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

        // Send snapshot at reduced rate
        if (tickCount % SNAPSHOT_DIV == 0) {
            GameSnapshot snap = GameSnapshot::fromWorld(world);
            snap.lastAckedInputTick[0] = clients[0].lastAckedInputTick;
            snap.lastAckedInputTick[1] = clients[1].lastAckedInputTick;

            for (int i = 0; i < 2; ++i) {
                auto& c = clients[i];
                if (!c.connected) continue;

                std::string payload;
                if (!lastSentSnap[i].has_value()) {
                    // First snapshot: always send full state so the client
                    // has a base to apply future deltas against.
                    payload = frameMessage(snap.toJson());
                } else {
                    auto delta = GameDeltaSnapshot::compute(*lastSentSnap[i], snap);
                    if (delta.has_value())
                        payload = frameMessage(delta->toJson());
                    // Nothing changed — skip sending this tick.
                }

                if (!payload.empty()) {
                    if (!sendAll(c.fd, payload)) {
                        std::cerr << "[server] send failed for player " << c.playerId << "\n";
                        c.connected = false;
                        continue;
                    }
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
