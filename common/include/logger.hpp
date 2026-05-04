#pragma once

#include <common/include/protocol.hpp>

#include <chrono>
#include <cstdio>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <string>

// ---------------------------------------------------------------------------
// ClientLogger
//
// Thread-safe, file-backed logger for client-side network and prediction
// diagnostics. Writes timestamped lines to a text file so you can grep
// specific categories (INPUT, SNAP, RECONCILE, RENDER) after a session.
//
// Usage:
//   ClientLogger log("/tmp/biplanes_client.log");  // prints path to stdout
//   log.logInput(tick, input);
//   log.logSnapshot("state", snap);
//   log.logReconcile(snapTick, ackedTick, histSize, predX, predY, srvX, srvY);
//   log.logRender(frameN, playerId, local, remote);
// ---------------------------------------------------------------------------
class ClientLogger
{
public:
    // Opens the log file and prints the resolved path to stdout.
    explicit ClientLogger(const std::string& path)
        : _path(path)
        , _start(std::chrono::steady_clock::now())
    {
        _file.open(path, std::ios::out | std::ios::trunc);
        if (_file.is_open())
            std::printf("[biplanes] Client log: %s\n", path.c_str());
        else
            std::printf("[biplanes] WARNING: could not open log file: %s\n", path.c_str());
    }

    const std::string& path() const { return _path; }
    bool               ok()   const { return _file.is_open(); }

    // Log an input message sent to the server.
    void logInput(uint64_t tick, const PlayerInput& input)
    {
        std::ostringstream ss;
        ss << tag("INPUT")
           << "tick=" << tick
           << " thr=" << static_cast<int>(input.throttle)
           << " pit=" << static_cast<int>(input.pitch)
           << " sht=" << input.shoot
           << " jmp=" << input.jump;
        if (input.joystick.active)
            ss << " js=(ang=" << input.joystick.angle
               << ",mag=" << input.joystick.magnitude << ")";
        write(ss.str());
    }

    // Log a received server snapshot (state or delta).
    void logSnapshot(const std::string& type, const GameSnapshot& snap)
    {
        std::ostringstream ss;
        ss << std::fixed << std::setprecision(3);
        ss << tag("SNAP")
           << "type=" << type
           << " tick=" << snap.tick
           << " ait=[" << snap.lastAckedInputTick[0] << "," << snap.lastAckedInputTick[1] << "]"
           << " p0=(x=" << snap.planes[0].x << ",y=" << snap.planes[0].y
               << ",dir=" << snap.planes[0].dir << ",dead=" << snap.planes[0].isDead << ")"
           << " p1=(x=" << snap.planes[1].x << ",y=" << snap.planes[1].y
               << ",dir=" << snap.planes[1].dir << ",dead=" << snap.planes[1].isDead << ")"
           << " bullets=" << snap.bullets.size();
        write(ss.str());
    }

    // Log a reconciliation event: prediction before/after vs server truth.
    void logReconcile(uint64_t snapTick, uint64_t ackedTick, std::size_t historySize,
                      float predX,  float predY,   // before reconcile
                      float postX,  float postY,   // after reconcile (server + replay)
                      float srvX,   float srvY)    // raw server snapshot position
    {
        const float dxPost = postX - srvX;
        const float dyPost = postY - srvY;
        const float distPost = std::sqrt(dxPost * dxPost + dyPost * dyPost);
        const float dxPre = predX - srvX;
        const float dyPre = predY - srvY;
        const float distPre = std::sqrt(dxPre * dxPre + dyPre * dyPre);
        std::ostringstream ss;
        ss << std::fixed << std::setprecision(4);
        ss << tag("RECONCILE")
           << "snap_tick=" << snapTick
           << " acked=" << ackedTick
           << " hist=" << historySize
           << " pre=(" << predX << "," << predY << ")"
           << " post=(" << postX << "," << postY << ")"
           << " srv=(" << srvX << "," << srvY << ")"
           << " pre_err=" << distPre
           << " post_err=" << distPost;
        write(ss.str());
    }

    // Log the rendered frame state. Call every N frames to avoid log spam.
    void logRender(uint64_t frameN, int playerId,
                   const PlaneSnapshot& local, const PlaneSnapshot& remote)
    {
        std::ostringstream ss;
        ss << std::fixed << std::setprecision(3);
        ss << tag("RENDER")
           << "frame=" << frameN
           << " pid=" << playerId
           << " local=(x=" << local.x << ",y=" << local.y
               << ",dir=" << local.dir << ",dead=" << local.isDead << ")"
           << " remote=(x=" << remote.x << ",y=" << remote.y
               << ",dir=" << remote.dir << ",dead=" << remote.isDead << ")";
        write(ss.str());
    }

private:
    std::string   _path;
    std::ofstream _file;
    std::mutex    _mutex;
    std::chrono::steady_clock::time_point _start;

    // Prefix: "[T+000.000s][CATEGORY] "
    std::string tag(const char* category)
    {
        using FpSec = std::chrono::duration<double>;
        double t = std::chrono::duration_cast<FpSec>(
            std::chrono::steady_clock::now() - _start).count();
        std::ostringstream ss;
        ss << "[T+" << std::fixed << std::setprecision(3) << t << "s]["
           << category << "] ";
        return ss.str();
    }

    void write(const std::string& line)
    {
        std::lock_guard<std::mutex> lk(_mutex);
        if (_file.is_open())
        {
            _file << line << '\n';
            _file.flush();
        }
    }
};
