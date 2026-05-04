#import "BiplanesBridge.h"

#include "core/include/world.hpp"
#include "core/include/bot.hpp"
#include "core/include/constants.hpp"
#include "common/include/protocol.hpp"
#include "common/include/interpolator.hpp"
#include "common/include/logger.hpp"
#include "common/include/predictor.hpp"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include <chrono>

static bool setNonBlocking(int fd)
{
    int flags = ::fcntl(fd, F_GETFL, 0);
    return flags != -1 && ::fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1;
}

static bool sendAll(int fd, const std::string& data)
{
    size_t sent = 0;
    while (sent < data.size())
    {
        ssize_t n = ::send(fd, data.data() + sent, data.size() - sent, MSG_NOSIGNAL);
        if (n <= 0)
            return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

static int connectTCP(const char* host, uint16_t port)
{
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (::inet_pton(AF_INET, host, &addr.sin_addr) <= 0)
    {
        ::close(fd);
        return -1;
    }
    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0)
    {
        ::close(fd);
        return -1;
    }
    int one = 1;
    ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    setNonBlocking(fd);
    return fd;
}

static BiplanesBridgeState* buildState(const GameSnapshot& gs)
{
    BiplanesBridgeState* state = [BiplanesBridgeState new];
    state.tick = gs.tick;
    state.roundRunning = gs.roundRunning;
    state.roundFinished = gs.roundFinished;
    state.winnerId = gs.winnerId;

    NSMutableArray<PlaneState*>* planes = [NSMutableArray arrayWithCapacity:2];
    for (int i = 0; i < 2; ++i)
    {
        const PlaneSnapshot& ps = gs.planes[i];
        PlaneState* p = [PlaneState new];
        p.x = ps.x;
        p.y = ps.y;
        p.dir = ps.dir;
        p.speed = ps.speed;
        p.hp = ps.hp;
        p.score = ps.score;
        p.isDead = ps.isDead;
        p.isOnGround = ps.isOnGround;
        p.isTakingOff = ps.isTakingOff;
        p.hasJumped = ps.hasJumped;
        p.protectionRemaining = ps.protectionRemaining;
        p.smokeFrame = ps.smokeFrame;
        p.fireFrame = ps.fireFrame;

        p.pilotX = ps.pilot.x;
        p.pilotY = ps.pilot.y;
        p.pilotIsDead = ps.pilot.isDead;
        p.pilotChuteOpen = ps.pilot.isChuteOpen;
        p.pilotChuteBroken = ps.pilot.isChuteBroken;
        p.pilotIsRunning = ps.pilot.isRunning;
        p.pilotFallFrame = ps.pilot.fallFrame;
        p.pilotRunFrame = ps.pilot.runFrame;
        p.pilotAngelFrame = ps.pilot.angelFrame;
        p.pilotDir = ps.pilot.dir;
        p.pilotIsMoving = std::abs(ps.pilot.speedX) > 0.0001f;
        [planes addObject:p];
    }
    state.planes = planes;

    NSMutableArray<BulletState*>* bullets =
        [NSMutableArray arrayWithCapacity:(NSUInteger)gs.bullets.size()];
    for (const auto& b : gs.bullets)
    {
        BulletState* bs = [BulletState new];
        bs.x = b.x;
        bs.y = b.y;
        bs.dir = b.dir;
        bs.firedBy = b.firedBy;
        [bullets addObject:bs];
    }
    state.bullets = bullets;
    return state;
}


@implementation PlaneState
@end
@implementation BulletState
@end
@implementation BiplanesBridgeState
@end


@interface BiplanesBridge ()
{
    GameWorld _world;
    BotAI _bot;

    std::atomic<int> _throttle;  // 0=idle 1=inc 2=dec
    std::atomic<int> _pitch;     // 0=idle 1=left 2=right
    std::atomic<bool> _shoot;
    std::atomic<bool> _jump;

    std::atomic<float> _jsAngle;
    std::atomic<float> _jsMag;
    std::atomic<bool> _jsActive;

    std::mutex _stateMutex;
    BiplanesBridgeState* _latestState;

    int _serverFd;
    std::vector<uint8_t> _netBuf;
    std::atomic<bool> _networkRunning;
    std::thread _networkThread;

    // Snapshot interpolation + client-side prediction
    SnapshotInterpolator        _interp;
    ClientPredictor             _predictor;
    std::mutex                  _interpMutex;   // guards _interp and _predictor (network thread writes)
    double                      _renderDelayMs; // 3 × snapshot interval
    std::atomic<uint64_t>       _predTick;   // local prediction tick counter (reset per session; atomic for network-thread read)
    uint64_t                    _lastReconciledSnapTick; // most recent snap tick reconciled on the main thread
    std::atomic<uint64_t>       _lastSentTick;        // highest predTick covered by a sent InputMessage

    // Wall-clock origin for interpolator timestamps
    std::chrono::steady_clock::time_point _interpOrigin;

    // Client diagnostic logger (created on connect, null offline)
    std::unique_ptr<ClientLogger> _logger;
    uint64_t                      _renderFrameN; // frame counter for render log throttle

    CADisplayLink* _displayLink;
    double _accumMs;
    std::chrono::steady_clock::time_point _lastTime;
    
    GameConnectionState _connectionState;
}
@end


@implementation BiplanesBridge

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _bot = BotAI{BotDifficulty::Easy};
        _serverFd = -1;
        _throttle = 0;
        _pitch = 0;
        _shoot = false;
        _jump = false;
        _jsAngle = 0.0f;
        _jsMag = 0.0f;
        _jsActive = false;
        _playerId = 0;
        _isConnected = NO;
        _isOffline = NO;
        _latestState = [BiplanesBridgeState new];
        _accumMs = 0.0;
        _predTick = 0;
        _lastSentTick = 0;
        _lastReconciledSnapTick = 0;
        _renderFrameN = 0;
        _networkRunning = false;
        _connectionState = GameConnectionStateConnecting;
        _renderDelayMs = 3.0 * (1000.0 / constants::snapshotRate);
        _interpOrigin = std::chrono::steady_clock::now();
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (void)setThrottle:(int)throttle
{
    _throttle = throttle;
}

- (void)setPitch:(int)pitch
{
    _pitch = pitch;
}

- (void)setShoot:(BOOL)shoot
{
    _shoot = (bool)shoot;
}

- (void)setJump:(BOOL)jump
{
    _jump = (bool)jump;
}

- (void)setJoystick:(float)angle magnitude:(float)magnitude active:(BOOL)active
{
    _jsAngle = angle;
    _jsMag = magnitude;
    _jsActive = (bool)active;
}

- (BiplanesBridgeState*)currentState
{
    std::lock_guard<std::mutex> lock(_stateMutex);
    return _latestState;
}

- (GameConnectionState)connectionState
{
    return _connectionState;
}

- (void)startOfflineMode
{
    _isOffline = YES;
    _isConnected = NO;
    _playerId = 0;
    _world = GameWorld{};
    _world.startRound();

    _lastTime = std::chrono::steady_clock::now();
    _accumMs = 0.0;

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_offlineTick:)];
    // Same minimum-60Hz constraint as the online display link — prevents ProMotion
    // from stalling the offline game loop on iPhone 15/16 Pro.
    if (@available(iOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    } else {
        _displayLink.preferredFramesPerSecond = 60;
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)_offlineTick:(CADisplayLink*)link
{
    auto now = std::chrono::steady_clock::now();
    using FpMs = std::chrono::duration<double, std::milli>;
    double frameMs = std::chrono::duration_cast<FpMs>(now - _lastTime).count();
    _lastTime = now;
    if (frameMs > 100.0)
        frameMs = 100.0;

    _accumMs += frameMs;
    const double TICK_MS = GameWorld::TICK_DT * 1000.0;

    while (_accumMs >= TICK_MS)
    {
        PlayerInput inputs[2];

        // Human input (player 0 = Blue)
        inputs[0].throttle = static_cast<PlaneThrottle>(_throttle.load());
        inputs[0].pitch = static_cast<PlanePitch>(_pitch.load());
        inputs[0].shoot = _shoot.load();
        inputs[0].jump = _jump.load();
        inputs[0].joystick.angle = _jsAngle.load();
        inputs[0].joystick.magnitude = _jsMag.load();
        inputs[0].joystick.active = _jsActive.load();

        // Bot input (player 1 = Red)
        inputs[1] = _bot.think(_world.planes[1],
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

- (void)startOnlineMode:(NSString*)host
                   port:(uint16_t)port
             completion:(void (^)(BOOL, NSString* _Nullable))completion
{
    _isOffline = NO;
    _connectionState = GameConnectionStateConnecting;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      int fd = connectTCP(host.UTF8String, port);
      if (fd < 0)
      {
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Could not connect to server");
          });
          return;
      }

      int assignedId = -1;
      {
          std::vector<uint8_t> buf;
          while (assignedId == -1)
          {
              // Temporarily blocking read for welcome
              uint8_t tmp[512];
              // Switch to blocking temporarily
              int flags = fcntl(fd, F_GETFL, 0);
              fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
              ssize_t n = ::recv(fd, tmp, sizeof(tmp), 0);
              fcntl(fd, F_SETFL, flags);  // restore non-blocking
              if (n <= 0)
                  break;
              buf.insert(buf.end(), tmp, tmp + n);
              std::string json = tryReadMessage(buf);
              if (!json.empty())
              {
                  try
                  {
                      auto wm = WelcomeMessage::fromJson(json);
                      assignedId = wm.playerId;
                  }
                  catch (...)
                  {}
              }
          }
      }

      if (assignedId < 0)
      {
          ::close(fd);
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"No welcome message from server");
          });
          return;
      }

      self->_serverFd = fd;
      self->_playerId = assignedId;
      self->_isConnected = YES;
      self->_networkRunning = true;

      // Reset smoothing state and prediction tick for the new session.
      {
          std::lock_guard<std::mutex> lk(self->_interpMutex);
          self->_interp    = SnapshotInterpolator{};
          self->_predictor = ClientPredictor{assignedId};
          self->_interpOrigin = std::chrono::steady_clock::now();
          self->_predTick  = 0;
          self->_lastSentTick = 0;
          self->_lastReconciledSnapTick = 0;
      }
      self->_renderFrameN = 0;

      // Open diagnostic log in the app's Documents directory.
      NSArray<NSString*>* docs = NSSearchPathForDirectoriesInDomains(
          NSDocumentDirectory, NSUserDomainMask, YES);
      NSString* logDir  = docs.firstObject ?: NSTemporaryDirectory();
      NSString* logPath = [logDir stringByAppendingPathComponent:@"biplanes_client.log"];
      self->_logger = std::make_unique<ClientLogger>(logPath.UTF8String);

      self->_networkThread = std::thread([self]() { [self _networkLoop]; });

      dispatch_async(dispatch_get_main_queue(), ^{
        self->_lastTime = std::chrono::steady_clock::now();
        self->_displayLink = [CADisplayLink displayLinkWithTarget:self
                                                         selector:@selector(_onlineTick:)];
        // Require minimum 60 Hz so ProMotion can't drop the display link below
        // 60 Hz (which would pause _onlineTick: for 66–366 ms and cause the
        // local plane to teleport on resume).  Allowing up to 120 Hz preserves
        // full ProMotion quality on iPhone 15/16 Pro.
        if (@available(iOS 15.0, *)) {
            self->_displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
        } else {
            self->_displayLink.preferredFramesPerSecond = 60;
        }
        [self->_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self->_connectionState = GameConnectionStateWaitingForPlayers;
        completion(YES, nil);
      });
    });
}

- (void)_networkLoop
{
    using Clk = std::chrono::steady_clock;
    using FpMs = std::chrono::duration<double, std::milli>;
    auto lastSend = Clk::now();
    const auto SEND_INTERVAL = std::chrono::milliseconds(16);  // ~60Hz send cadence

    while (_networkRunning.load())
    {
        // Send inputs at ~60Hz.  At 120Hz display the predictor advances 2 ticks
        // between sends; we cover both ticks by sending one InputMessage per
        // uncovered predTick so the server acks the highest tick and the predictor
        // history is pruned correctly (max 3 messages per interval as a safety cap).
        auto now = Clk::now();
        if (now - lastSend >= SEND_INTERVAL)
        {
            const uint64_t curTick  = _predTick.load();
            const uint64_t prevSent = _lastSentTick.load();

            // Build the input payload once — same state for all ticks in this burst.
            InputMessage msg;
            msg.throttle = static_cast<PlaneThrottle>(_throttle.load());
            msg.pitch    = static_cast<PlanePitch>(_pitch.load());
            msg.shoot    = _shoot.load();
            msg.jump     = _jump.load();
            msg.jsActive = _jsActive.load();
            msg.jsAngle  = _jsAngle.load();
            msg.jsMag    = _jsMag.load();

            // Cap the burst at 3 to avoid flooding on stalls.
            const uint64_t startTick = (curTick > prevSent + 3)
                                       ? curTick - 2
                                       : prevSent + 1;

            for (uint64_t t = startTick; t <= curTick; ++t)
            {
                msg.tick = t;
                if (!sendAll(_serverFd, frameMessage(msg.toJson())))
                {
                    _networkRunning = false;
                    break;
                }
                if (_logger)
                {
                    PlayerInput pi{};
                    pi.throttle           = msg.throttle;
                    pi.pitch              = msg.pitch;
                    pi.shoot              = msg.shoot;
                    pi.jump               = msg.jump;
                    pi.joystick.active    = msg.jsActive;
                    pi.joystick.angle     = msg.jsAngle;
                    pi.joystick.magnitude = msg.jsMag;
                    _logger->logInput(t, pi);
                }
            }
            if (!_networkRunning.load()) break;

            _lastSentTick.store(curTick);
            lastSend = now;
        }

        {
            uint8_t tmp[8192];
            ssize_t n;
            while ((n = ::recv(_serverFd, tmp, sizeof(tmp), 0)) > 0)
                _netBuf.insert(_netBuf.end(), tmp, tmp + n);
        }

        std::string json;
        while (!(json = tryReadMessage(_netBuf)).empty())
        {
            try
            {
                auto j = nlohmann::json::parse(json);
                const std::string type = j.value("type", std::string{});

                GameSnapshot snap;
                bool valid = false;

                if (type == "state")
                {
                    snap  = GameSnapshot::fromJson(json);
                    valid = true;
                }
                else if (type == "delta")
                {
                    std::lock_guard<std::mutex> lk(_interpMutex);
                    const GameSnapshot* base = _interp.latest();
                    if (base)
                    {
                        snap  = GameDeltaSnapshot::fromJson(json).apply(*base);

                        if (_logger) _logger->logSnapshot("delta", snap);

                        double recvMs = std::chrono::duration_cast<FpMs>(
                            Clk::now() - _interpOrigin).count();
                        _interp.push(snap, recvMs);
                    }
                    _connectionState = GameConnectionStateRunning;
                    continue;  // already handled under lock
                }

                if (valid)
                {
                    if (_logger) _logger->logSnapshot("state", snap);

                    double recvMs = std::chrono::duration_cast<FpMs>(
                        Clk::now() - _interpOrigin).count();
                    {
                        std::lock_guard<std::mutex> lk(_interpMutex);
                        _interp.push(snap, recvMs);
                    }
                    _connectionState = GameConnectionStateRunning;
                }
            }
            catch (...)
            {}
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    if (_serverFd >= 0)
    {
        ::close(_serverFd);
        _serverFd = -1;
    }
    _isConnected = NO;
}

- (void)_onlineTick:(CADisplayLink*)link
{
    using Clk  = std::chrono::steady_clock;
    using FpMs = std::chrono::duration<double, std::milli>;

    auto now = Clk::now();
    double frameMs = std::chrono::duration_cast<FpMs>(now - _lastTime).count();
    _lastTime = now;

    // Collect current input snapshot.
    PlayerInput input{};
    input.throttle         = static_cast<PlaneThrottle>(_throttle.load());
    input.pitch            = static_cast<PlanePitch>(_pitch.load());
    input.shoot            = _shoot.load();
    input.jump             = _jump.load();
    input.joystick.angle   = _jsAngle.load();
    input.joystick.magnitude = _jsMag.load();
    input.joystick.active  = _jsActive.load();

    // Advance prediction world at 120 Hz (same rate as server).
    // Cap to 3 ticks per call to prevent large catch-up bursts when the main
    // thread is stalled (e.g. Swift UI work). Bursting 12 ticks at once after a
    // stall places the plane 12 ticks ahead, which snaps back visibly on the
    // next reconcile. At 60 fps we normally apply exactly 2 ticks per frame;
    // allowing 3 absorbs mild timing jitter without permitting large overshoots.
    const double TICK_MS = GameWorld::TICK_DT * 1000.0;
    // Clamp the raw elapsed time before accumulating ticks.  CAFrameRateRange
    // with minimum=60 Hz should prevent long pauses on ProMotion devices, but
    // as a safety net we cap frameMs to 2.5 ticks (~20 ms).  Any genuine stall
    // longer than that would cause a large catch-up burst which snaps visibly.
    if (frameMs > TICK_MS * 2.5) frameMs = TICK_MS * 2.5;
    _accumMs += frameMs;
    if (_accumMs > TICK_MS * 3.0) _accumMs = TICK_MS * 3.0;

    {
        std::lock_guard<std::mutex> lk(_interpMutex);

        // Blend out any pending visual correction from previous reconciles.
        // Must happen before reconcile so this frame's blend step is applied
        // before a new correction is (potentially) added.
        _predictor.blendStep(frameMs);

        // Reconcile once per frame with the newest server snapshot available.
        // Doing this on the main thread (rather than from the network thread
        // every time a packet arrives) prevents snapshot bursts from triggering
        // multiple sequential reconcile calls in the same render frame, which
        // would cumulatively push the prediction far forward and then snap back.
        if (const GameSnapshot* latest = _interp.latest())
        {
            if (latest->tick > _lastReconciledSnapTick)
            {
                const PlaneSnapshot prePhys = _predictor.physicsLocalPlane();
                _predictor.reconcile(*latest);
                const PlaneSnapshot postPhys = _predictor.physicsLocalPlane();
                if (_logger) _logger->logReconcile(
                    latest->tick, latest->lastAckedInputTick[_playerId],
                    _predictor.historySize(),
                    prePhys.x, prePhys.y,
                    postPhys.x, postPhys.y,
                    latest->planes[_playerId].x, latest->planes[_playerId].y);
                _lastReconciledSnapTick = latest->tick;
            }
        }

        while (_accumMs >= TICK_MS)
        {
            _predictor.applyInput(++_predTick, input);
            _accumMs -= TICK_MS;
        }
    }

    // Build render state: local plane from prediction, remote from interpolator.
    double nowMs = std::chrono::duration_cast<FpMs>(now - _interpOrigin).count();

    GameSnapshot render;
    bool hasData = false;
    {
        std::lock_guard<std::mutex> lk(_interpMutex);
        if (!_interp.empty())
        {
            render = _interp.interpolated(nowMs - _renderDelayMs);
            render.planes[_playerId] = _predictor.localPlane();
            hasData = true;
        }
    }

    if (hasData)
    {
        BiplanesBridgeState* state = buildState(render);
        {
            std::lock_guard<std::mutex> lock(_stateMutex);
            _latestState = state;
        }

        // Log render state every 10 frames (~6/sec at 60 Hz) for flicker diagnosis.
        ++_renderFrameN;
        if (_logger && (_renderFrameN % 10 == 0))
        {
            _logger->logRender(_renderFrameN, _playerId,
                render.planes[_playerId],
                render.planes[1 - _playerId]);
        }
    }
}

- (void)stop
{
    [_displayLink invalidate];
    _displayLink = nil;

    _networkRunning = false;
    if (_networkThread.joinable())
        _networkThread.join();

    if (_serverFd >= 0)
    {
        ::close(_serverFd);
        _serverFd = -1;
    }

    _isConnected = NO;
    _isOffline = NO;
}

@end
