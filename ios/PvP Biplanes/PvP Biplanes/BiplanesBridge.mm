// BiplanesBridge.mm — Obj-C++ implementation.
// This is the ONLY file that includes C++ game-core headers.

#import "BiplanesBridge.h"

// ── C++ game core ────────────────────────────────────────────────────────────
#include "core/include/world.hpp"
#include "core/include/bot.hpp"
#include "common/include/protocol.hpp"

// ── POSIX networking ─────────────────────────────────────────────────────────
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

// ── std ───────────────────────────────────────────────────────────────────────
#include <atomic>
#include <mutex>
#include <thread>
#include <vector>
#include <chrono>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static bool setNonBlocking(int fd)
{
    int flags = ::fcntl(fd, F_GETFL, 0);
    return flags != -1 && ::fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1;
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

static int connectTCP(const char* host, uint16_t port)
{
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(port);
    if (::inet_pton(AF_INET, host, &addr.sin_addr) <= 0) { ::close(fd); return -1; }
    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        ::close(fd); return -1;
    }
    int one = 1;
    ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    setNonBlocking(fd);
    return fd;
}

// ---------------------------------------------------------------------------
// Snapshot builder — GameSnapshot → Obj-C objects
// ---------------------------------------------------------------------------
static BiplanesBridgeState* buildState(const GameSnapshot& gs)
{
    BiplanesBridgeState* state = [BiplanesBridgeState new];
    state.tick          = gs.tick;
    state.roundRunning  = gs.roundRunning;
    state.roundFinished = gs.roundFinished;
    state.winnerId      = gs.winnerId;

    NSMutableArray<PlaneState*>* planes = [NSMutableArray arrayWithCapacity:2];
    for (int i = 0; i < 2; ++i) {
        const PlaneSnapshot& ps = gs.planes[i];
        PlaneState* p = [PlaneState new];
        p.x     = ps.x;  p.y   = ps.y;  p.dir = ps.dir;
        p.speed = ps.speed;
        p.hp    = ps.hp; p.score = ps.score;
        p.isDead      = ps.isDead;
        p.isOnGround  = ps.isOnGround;
        p.isTakingOff = ps.isTakingOff;
        p.hasJumped   = ps.hasJumped;
        p.protectionRemaining = ps.protectionRemaining;

        p.pilotX          = ps.pilot.x;
        p.pilotY          = ps.pilot.y;
        p.pilotIsDead     = ps.pilot.isDead;
        p.pilotChuteOpen  = ps.pilot.isChuteOpen;
        p.pilotChuteBroken= ps.pilot.isChuteBroken;
        p.pilotIsRunning  = ps.pilot.isRunning;
        [planes addObject:p];
    }
    state.planes = planes;

    NSMutableArray<BulletState*>* bullets = [NSMutableArray arrayWithCapacity:(NSUInteger)gs.bullets.size()];
    for (const auto& b : gs.bullets) {
        BulletState* bs = [BulletState new];
        bs.x = b.x; bs.y = b.y; bs.dir = b.dir; bs.firedBy = b.firedBy;
        [bullets addObject:bs];
    }
    state.bullets = bullets;
    return state;
}

// ---------------------------------------------------------------------------
// @implementation stubs for data objects
// ---------------------------------------------------------------------------
@implementation PlaneState @end
@implementation BulletState @end
@implementation BiplanesBridgeState @end

// ---------------------------------------------------------------------------
// BiplanesBridge private extension
// ---------------------------------------------------------------------------
@interface BiplanesBridge ()
{
    // Game state (protected by _stateMutex)
    GameWorld   _world;
    BotAI       _bot;

    // Serialised human input (written on main thread, read on game thread)
    std::atomic<int>   _throttle;  // 0=idle 1=inc 2=dec
    std::atomic<int>   _pitch;     // 0=idle 1=left 2=right
    std::atomic<bool>  _shoot;
    std::atomic<bool>  _jump;
    // Analog joystick state (written on main thread, read on game thread)
    std::atomic<float> _jsAngle;
    std::atomic<float> _jsMag;
    std::atomic<bool>  _jsActive;

    // Latest snapshot (protected by _stateMutex)
    std::mutex          _stateMutex;
    BiplanesBridgeState* _latestState;

    // Networking (online mode)
    int             _serverFd;
    std::vector<uint8_t> _netBuf;
    std::atomic<bool> _networkRunning;
    std::thread       _networkThread;

    // Display link (offline fixed-step loop)
    CADisplayLink* _displayLink;
    double         _accumMs;
    std::chrono::steady_clock::time_point _lastTime;
}
@end

// ---------------------------------------------------------------------------
// @implementation BiplanesBridge
// ---------------------------------------------------------------------------
@implementation BiplanesBridge

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bot         = BotAI{BotDifficulty::Medium};
        _serverFd    = -1;
        _throttle    = 0;
        _pitch       = 0;
        _shoot       = false;
        _jump        = false;
        _jsAngle     = 0.0f;
        _jsMag       = 0.0f;
        _jsActive    = false;
        _playerId    = 0;
        _isConnected = NO;
        _isOffline   = NO;
        _latestState = [BiplanesBridgeState new];
        _accumMs     = 0.0;
        _networkRunning = false;
    }
    return self;
}

- (void)dealloc { [self stop]; }

// ── Input ──────────────────────────────────────────────────────────────────

- (void)setThrottle:(int)throttle { _throttle = throttle; }
- (void)setPitch:(int)pitch       { _pitch    = pitch; }
- (void)setShoot:(BOOL)shoot      { _shoot    = (bool)shoot; }
- (void)setJump:(BOOL)jump        { _jump     = (bool)jump; }
- (void)setJoystick:(float)angle magnitude:(float)magnitude active:(BOOL)active
{
    _jsAngle  = angle;
    _jsMag    = magnitude;
    _jsActive = (bool)active;
}

// ── State ─────────────────────────────────────────────────────────────────

- (BiplanesBridgeState*)currentState
{
    std::lock_guard<std::mutex> lock(_stateMutex);
    return _latestState;
}

// ── Offline mode ──────────────────────────────────────────────────────────

- (void)startOfflineMode
{
    _isOffline   = YES;
    _isConnected = NO;
    _playerId    = 0;
    _world       = GameWorld{};
    _world.startRound();

    _lastTime    = std::chrono::steady_clock::now();
    _accumMs     = 0.0;

    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                               selector:@selector(_offlineTick:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];
}

- (void)_offlineTick:(CADisplayLink*)link
{
    auto now     = std::chrono::steady_clock::now();
    using FpMs   = std::chrono::duration<double, std::milli>;
    double frameMs = std::chrono::duration_cast<FpMs>(now - _lastTime).count();
    _lastTime    = now;
    if (frameMs > 100.0) frameMs = 100.0;

    _accumMs += frameMs;
    const double TICK_MS = GameWorld::TICK_DT * 1000.0;

    while (_accumMs >= TICK_MS) {
        PlayerInput inputs[2];

        // Human input (player 0 = Blue)
        inputs[0].throttle        = static_cast<PlaneThrottle>(_throttle.load());
        inputs[0].pitch           = static_cast<PlanePitch>   (_pitch.load());
        inputs[0].shoot           = _shoot.load();
        inputs[0].jump            = _jump.load();
        inputs[0].joystick.angle  = _jsAngle.load();
        inputs[0].joystick.magnitude = _jsMag.load();
        inputs[0].joystick.active = _jsActive.load();

        // Bot input (player 1 = Red)
        inputs[1] = _bot.think(
            _world.planes[1],
            _world.planes[0],
            _world.bullets.instances(),
            static_cast<float>(GameWorld::TICK_DT));

        _world.update(inputs);
        _accumMs -= TICK_MS;
    }

    GameSnapshot snap = GameSnapshot::fromWorld(_world);
    BiplanesBridgeState* state = buildState(snap);
    {
        std::lock_guard<std::mutex> lock(_stateMutex);
        _latestState = state;
    }
}

// ── Online mode ───────────────────────────────────────────────────────────

- (void)startOnlineMode:(NSString*)host
                   port:(uint16_t)port
             completion:(void(^)(BOOL, NSString* _Nullable))completion
{
    _isOffline = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int fd = connectTCP(host.UTF8String, port);
        if (fd < 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Could not connect to server");
            });
            return;
        }

        // Wait for welcome message (blocking; still on background thread)
        int assignedId = -1;
        {
            std::vector<uint8_t> buf;
            while (assignedId == -1) {
                // Temporarily blocking read for welcome
                uint8_t tmp[512];
                // Switch to blocking temporarily
                int flags = fcntl(fd, F_GETFL, 0);
                fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
                ssize_t n = ::recv(fd, tmp, sizeof(tmp), 0);
                fcntl(fd, F_SETFL, flags);  // restore non-blocking
                if (n <= 0) break;
                buf.insert(buf.end(), tmp, tmp + n);
                std::string json = tryReadMessage(buf);
                if (!json.empty()) {
                    try {
                        auto wm  = WelcomeMessage::fromJson(json);
                        assignedId = wm.playerId;
                    } catch (...) {}
                }
            }
        }

        if (assignedId < 0) {
            ::close(fd);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"No welcome message from server");
            });
            return;
        }

        self->_serverFd      = fd;
        self->_playerId      = assignedId;
        self->_isConnected   = YES;
        self->_networkRunning = true;

        // Start I/O thread
        self->_networkThread = std::thread([self]() {
            [self _networkLoop];
        });

        // Start display link for rendering updates
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_lastTime  = std::chrono::steady_clock::now();
            self->_displayLink = [CADisplayLink displayLinkWithTarget:self
                                                              selector:@selector(_onlineTick:)];
            [self->_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                                     forMode:NSRunLoopCommonModes];
            completion(YES, nil);
        });
    });
}

- (void)_networkLoop
{
    uint64_t inputTick = 0;
    using Clk = std::chrono::steady_clock;
    auto lastSend = Clk::now();
    const auto SEND_INTERVAL = std::chrono::milliseconds(16);  // ~60Hz

    while (_networkRunning.load()) {
        // ── Send input at ~60Hz ────────────────────────────────────────────
        auto now = Clk::now();
        if (now - lastSend >= SEND_INTERVAL) {
            InputMessage msg;
            msg.tick     = ++inputTick;
            msg.throttle = static_cast<PlaneThrottle>(_throttle.load());
            msg.pitch    = static_cast<PlanePitch>   (_pitch.load());
            msg.shoot    = _shoot.load();
            msg.jump     = _jump.load();
            msg.jsActive = _jsActive.load();
            msg.jsAngle  = _jsAngle.load();
            msg.jsMag    = _jsMag.load();

            if (!sendAll(_serverFd, frameMessage(msg.toJson()))) {
                _networkRunning = false;
                break;
            }
            lastSend = now;
        }

        // ── Receive available data ─────────────────────────────────────────
        {
            uint8_t tmp[8192];
            ssize_t n;
            while ((n = ::recv(_serverFd, tmp, sizeof(tmp), 0)) > 0)
                _netBuf.insert(_netBuf.end(), tmp, tmp + n);
        }

        std::string json;
        while (!(json = tryReadMessage(_netBuf)).empty()) {
            try {
                GameSnapshot snap = GameSnapshot::fromJson(json);
                BiplanesBridgeState* state = buildState(snap);
                {
                    std::lock_guard<std::mutex> lock(_stateMutex);
                    _latestState = state;
                }
            } catch (...) {}
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    if (_serverFd >= 0) {
        ::close(_serverFd);
        _serverFd = -1;
    }
    _isConnected = NO;
}

- (void)_onlineTick:(CADisplayLink*)link
{
    // In online mode the state is already updated by the network thread.
    // This tick does nothing — GameScene reads currentState each frame.
    (void)link;
}

// ── Stop ──────────────────────────────────────────────────────────────────

- (void)stop
{
    [_displayLink invalidate];
    _displayLink = nil;

    _networkRunning = false;
    if (_networkThread.joinable()) _networkThread.join();

    if (_serverFd >= 0) { ::close(_serverFd); _serverFd = -1; }

    _isConnected = NO;
    _isOffline   = NO;
}

@end
