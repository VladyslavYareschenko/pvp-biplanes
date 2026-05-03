#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>


@interface PlaneState : NSObject
@property float x, y;
@property float dir;
@property float speed;

@property int hp;
@property int score;

@property BOOL isDead;
@property BOOL isOnGround;
@property BOOL isTakingOff;
@property BOOL hasJumped;

@property float protectionRemaining;
@property uint8_t smokeFrame;  // 0 = no smoke, 1-4 = frame index
@property int8_t fireFrame;    // -1 = no fire, 0-2 = frame index

@property float pilotX, pilotY;

@property BOOL pilotIsDead;
@property BOOL pilotIsRunning;
@property BOOL pilotChuteOpen;
@property BOOL pilotChuteBroken;

@property int8_t pilotFallFrame;   // 0-2
@property uint8_t pilotRunFrame;   // 0-3
@property int8_t pilotAngelFrame;  // 0-3 (when pilot is dead)
@property int16_t pilotDir;        // movement direction in degrees (0=up, 90=right)
@property BOOL pilotIsMoving;      // YES when pilot has non-zero move speed on ground
@end


@interface BulletState : NSObject
@property float x, y;
@property float dir;
@property uint8_t firedBy;  // 0=Blue, 1=Red
@end


@interface BiplanesBridgeState : NSObject
@property uint64_t tick;
@property NSArray<PlaneState*>* planes;  // always 2 elements
@property NSArray<BulletState*>* bullets;
@property BOOL roundRunning;
@property BOOL roundFinished;
@property int winnerId;  // -1 = none
@end


/*
 * BiplanesBridge — the single gateway between C++ and Swift.
 */

typedef NS_ENUM(NSInteger, GameConnectionState) {
    GameConnectionStateConnecting = 0,
    GameConnectionStateWaitingForPlayers = 1,
    GameConnectionStateRunning = 2,
};

@interface BiplanesBridge : NSObject

// Assigned player slot: 0 = Blue, 1 = Red.
@property (readonly) int playerId;

// YES once a server welcome message has been received (online mode).
@property (readonly) BOOL isConnected;

/// YES when running without a server.
@property (readonly) BOOL isOffline;

// Current connection state for online mode.
@property (readonly) GameConnectionState connectionState;

// Start a local game vs bot immediately.
- (void)startOfflineMode;

// Connect to server. StateCallback is called on main thread when connection state changes.
// Completion is called on main thread with success/error only for initial connection failures.
- (void)startOnlineMode:(NSString*)host
                   port:(uint16_t)port
             completion:(void (^)(BOOL success, NSString* _Nullable error))completion;

// Stop game loop and close any connection.
- (void)stop;

// throttle: 0=idle  1=increase  2=decrease
- (void)setThrottle:(int)throttle;

// pitch:    0=idle  1=left 2=right
- (void)setPitch:(int)pitch;

- (void)setShoot:(BOOL)shoot;

- (void)setJump:(BOOL)jump;

// Analog joystick — when active, overrides throttle + pitch for flight.
//   angle    : target heading in game degrees (0=up, 90=right, 180=down, 270=left)
//   magnitude: stick deflection [0.0 … 1.0]
//   active   : YES while touch is held, NO on release
- (void)setJoystick:(float)angle magnitude:(float)magnitude active:(BOOL)active;

// Returns the latest game state snapshot. Never nil after start.
- (BiplanesBridgeState*)currentState;

@end
