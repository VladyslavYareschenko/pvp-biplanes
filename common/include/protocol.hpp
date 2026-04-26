#pragma once

#include <core/include/types.hpp>
#include <core/include/world.hpp>

#include <nlohmann/json.hpp>

#include <string>
#include <vector>
#include <cstdint>
#include <cmath>
#include <stdexcept>

// ---------------------------------------------------------------------------
// Framing: 4-byte big-endian length prefix + JSON bytes
// ---------------------------------------------------------------------------
inline std::string frameMessage(const std::string& json)
{
    const uint32_t len = static_cast<uint32_t>(json.size());
    std::string out(4 + len, '\0');
    out[0] = static_cast<char>((len >> 24) & 0xFF);
    out[1] = static_cast<char>((len >> 16) & 0xFF);
    out[2] = static_cast<char>((len >>  8) & 0xFF);
    out[3] = static_cast<char>( len        & 0xFF);
    out.replace(4, len, json);
    return out;
}

// Returns complete JSON string if a full message is available in buf,
// advancing buf past the consumed bytes. Returns "" if not enough data yet.
inline std::string tryReadMessage(std::vector<uint8_t>& buf)
{
    if (buf.size() < 4) return {};

    const uint32_t len =
        (static_cast<uint32_t>(buf[0]) << 24) |
        (static_cast<uint32_t>(buf[1]) << 16) |
        (static_cast<uint32_t>(buf[2]) <<  8) |
         static_cast<uint32_t>(buf[3]);

    if (buf.size() < 4 + len) return {};

    std::string json(reinterpret_cast<char*>(buf.data() + 4), len);
    buf.erase(buf.begin(), buf.begin() + 4 + len);
    return json;
}

// ---------------------------------------------------------------------------
// Client → Server: player input
// ---------------------------------------------------------------------------
struct InputMessage
{
    uint64_t      tick     {};
    PlaneThrottle throttle {PlaneThrottle::Idle};
    PlanePitch    pitch    {PlanePitch::Idle};
    bool          shoot    {};
    bool          jump     {};
    // Analog joystick (optional, client sets jsActive=true when using joystick)
    bool          jsActive {};
    float         jsAngle  {};  // degrees [0, 360)
    float         jsMag    {};  // magnitude [0, 1]

    std::string toJson() const
    {
        nlohmann::json j;
        j["type"]     = "input";
        j["tick"]     = tick;
        j["throttle"] = static_cast<int>(throttle);
        j["pitch"]    = static_cast<int>(pitch);
        j["shoot"]    = shoot;
        j["jump"]     = jump;
        j["jsActive"] = jsActive;
        j["jsAngle"]  = jsAngle;
        j["jsMag"]    = jsMag;
        return j.dump();
    }

    static InputMessage fromJson(const std::string& s)
    {
        auto j = nlohmann::json::parse(s);
        InputMessage m;
        m.tick     = j.value("tick",     uint64_t{0});
        m.throttle = static_cast<PlaneThrottle>(j.value("throttle", 0));
        m.pitch    = static_cast<PlanePitch>   (j.value("pitch",    0));
        m.shoot    = j.value("shoot",    false);
        m.jump     = j.value("jump",     false);
        m.jsActive = j.value("jsActive", false);
        // Clamp to valid ranges for server-side safety.
        const float rawAngle = j.value("jsAngle", 0.0f);
        const float rawMag   = j.value("jsMag",   0.0f);
        m.jsAngle = rawAngle - 360.0f * std::floor(rawAngle / 360.0f); // [0, 360)
        m.jsMag   = std::max(0.0f, std::min(1.0f, rawMag));
        return m;
    }
};

// ---------------------------------------------------------------------------
// Server → Client: welcome message (assign player slot)
// ---------------------------------------------------------------------------
struct WelcomeMessage
{
    int playerId{};  // 0 = Blue, 1 = Red

    std::string toJson() const
    {
        nlohmann::json j;
        j["type"]     = "welcome";
        j["playerId"] = playerId;
        return j.dump();
    }

    static WelcomeMessage fromJson(const std::string& s)
    {
        auto j = nlohmann::json::parse(s);
        WelcomeMessage m;
        m.playerId = j.value("playerId", 0);
        return m;
    }
};

// ---------------------------------------------------------------------------
// Server → Client: full game state snapshot
// ---------------------------------------------------------------------------
struct PilotSnapshot
{
    float      x{}, y{};
    bool       isDead     {};
    bool       isChuteOpen{};
    bool       isChuteBroken{};
    bool       isRunning  {};
    float      speedX{}, speedY{};
    int8_t     fallFrame  {};
    uint8_t    runFrame   {};
    int8_t     angelFrame {};
    int16_t    dir        {};
    uint8_t    chuteState {};
};

struct PlaneSnapshot
{
    float   x{}, y{}, dir{};
    float   speed{};
    uint8_t hp    {};
    uint8_t score {};
    bool    isDead{};
    bool    isOnGround{};
    bool    isTakingOff{};
    bool    hasJumped  {};
    float   deadCooldownRemaining{};
    float   protectionRemaining  {};
    uint8_t smokeFrame {};
    int8_t  fireFrame  {};
    PilotSnapshot pilot{};
};

struct BulletSnapshot
{
    float   x{}, y{}, dir{};
    uint8_t firedBy{};  // 0=Blue, 1=Red
};

struct GameSnapshot
{
    uint64_t              tick{};
    PlaneSnapshot         planes[2]{};
    std::vector<BulletSnapshot> bullets{};
    bool    roundRunning  {};
    bool    roundFinished {};
    int     winnerId      {-1};

    static PlaneSnapshot fromPlane(const Plane& p)
    {
        PlaneSnapshot s;
        s.x     = p.x();
        s.y     = p.y();
        s.dir   = p.dir();
        s.speed = p.speed();
        s.hp    = p.hp();
        s.score = p.score();
        s.isDead      = p.isPlaneBodyDead();
        s.isOnGround  = p.isOnGround();
        s.isTakingOff = p.isTakingOff();
        s.hasJumped   = p.hasJumped();
        s.deadCooldownRemaining = p.deadCooldownRemainder();
        s.protectionRemaining   = p.protectionRemainder();
        s.smokeFrame = p.smokeFrame();
        s.fireFrame  = p.fireFrame();

        const auto& pilot = p.pilot;
        s.pilot.x            = pilot.x();
        s.pilot.y            = pilot.y();
        s.pilot.isDead       = pilot.isDead();
        s.pilot.isChuteOpen  = pilot.isChuteOpen();
        s.pilot.isChuteBroken= pilot.isChuteBroken();
        s.pilot.isRunning    = pilot.isRunning();
        s.pilot.speedX       = pilot.speedVec().x;
        s.pilot.speedY       = pilot.speedVec().y;
        s.pilot.fallFrame    = pilot.fallFrame();
        s.pilot.runFrame     = pilot.runFrame();
        s.pilot.angelFrame   = pilot.angelFrame();
        s.pilot.dir          = pilot.dir();
        s.pilot.chuteState   = static_cast<uint8_t>(pilot.chuteState());
        return s;
    }

    static GameSnapshot fromWorld(const GameWorld& w)
    {
        GameSnapshot s;
        s.tick          = w.tick;
        s.roundRunning  = w.roundRunning;
        s.roundFinished = w.roundFinished;
        s.winnerId      = w.winnerId;
        s.planes[0]     = fromPlane(w.planes[0]);
        s.planes[1]     = fromPlane(w.planes[1]);
        for (const auto& b : w.bullets.instances())
            s.bullets.push_back({b.x(), b.y(), b.dir(), static_cast<uint8_t>(b.firedBy())});
        return s;
    }

    std::string toJson() const
    {
        nlohmann::json j;
        j["type"]          = "state";
        j["tick"]          = tick;
        j["roundRunning"]  = roundRunning;
        j["roundFinished"] = roundFinished;
        j["winnerId"]      = winnerId;

        auto serPlane = [](const PlaneSnapshot& p) {
            nlohmann::json pj;
            pj["x"]    = p.x;    pj["y"]  = p.y;  pj["dir"] = p.dir;
            pj["speed"] = p.speed;
            pj["hp"]   = p.hp;   pj["score"] = p.score;
            pj["isDead"]      = p.isDead;
            pj["isOnGround"]  = p.isOnGround;
            pj["isTakingOff"] = p.isTakingOff;
            pj["hasJumped"]   = p.hasJumped;
            pj["deadCR"]      = p.deadCooldownRemaining;
            pj["protR"]       = p.protectionRemaining;
            pj["smokeFrame"]  = p.smokeFrame;
            pj["fireFrame"]   = p.fireFrame;
            nlohmann::json pt;
            pt["x"]         = p.pilot.x;          pt["y"]         = p.pilot.y;
            pt["isDead"]    = p.pilot.isDead;
            pt["chuteOpen"] = p.pilot.isChuteOpen;
            pt["chuteBroken"]=p.pilot.isChuteBroken;
            pt["running"]   = p.pilot.isRunning;
            pt["sx"]        = p.pilot.speedX;      pt["sy"]        = p.pilot.speedY;
            pt["fallFrame"] = p.pilot.fallFrame;
            pt["runFrame"]  = p.pilot.runFrame;
            pt["angelFrame"]= p.pilot.angelFrame;
            pt["dir"]       = p.pilot.dir;
            pt["chuteState"]= p.pilot.chuteState;
            pj["pilot"]     = pt;
            return pj;
        };

        j["planes"] = nlohmann::json::array();
        j["planes"].push_back(serPlane(planes[0]));
        j["planes"].push_back(serPlane(planes[1]));

        j["bullets"] = nlohmann::json::array();
        for (const auto& b : bullets) {
            nlohmann::json bj;
            bj["x"] = b.x; bj["y"] = b.y; bj["dir"] = b.dir; bj["by"] = b.firedBy;
            j["bullets"].push_back(bj);
        }
        return j.dump();
    }

    static GameSnapshot fromJson(const std::string& s)
    {
        auto j = nlohmann::json::parse(s);
        GameSnapshot gs;
        gs.tick          = j.value("tick",          uint64_t{0});
        gs.roundRunning  = j.value("roundRunning",  false);
        gs.roundFinished = j.value("roundFinished", false);
        gs.winnerId      = j.value("winnerId",      -1);

        auto desPlane = [](const nlohmann::json& pj, PlaneSnapshot& p) {
            p.x    = pj.value("x",    0.f); p.y   = pj.value("y",   0.f);
            p.dir  = pj.value("dir",  0.f); p.speed = pj.value("speed", 0.f);
            p.hp   = pj.value("hp",   uint8_t{0}); p.score = pj.value("score", uint8_t{0});
            p.isDead      = pj.value("isDead",      false);
            p.isOnGround  = pj.value("isOnGround",  false);
            p.isTakingOff = pj.value("isTakingOff", false);
            p.hasJumped   = pj.value("hasJumped",   false);
            p.deadCooldownRemaining = pj.value("deadCR", 0.f);
            p.protectionRemaining   = pj.value("protR",  0.f);
            p.smokeFrame = pj.value("smokeFrame", uint8_t{0});
            p.fireFrame  = pj.value("fireFrame",  int8_t{0});
            if (pj.contains("pilot")) {
                const auto& pt = pj["pilot"];
                p.pilot.x          = pt.value("x",          0.f);
                p.pilot.y          = pt.value("y",          0.f);
                p.pilot.isDead     = pt.value("isDead",     false);
                p.pilot.isChuteOpen= pt.value("chuteOpen",  false);
                p.pilot.isChuteBroken=pt.value("chuteBroken",false);
                p.pilot.isRunning  = pt.value("running",    false);
                p.pilot.speedX     = pt.value("sx",         0.f);
                p.pilot.speedY     = pt.value("sy",         0.f);
                p.pilot.fallFrame  = pt.value("fallFrame",  int8_t{0});
                p.pilot.runFrame   = pt.value("runFrame",   uint8_t{0});
                p.pilot.angelFrame = pt.value("angelFrame", int8_t{0});
                p.pilot.dir        = pt.value("dir",        int16_t{0});
                p.pilot.chuteState = pt.value("chuteState", uint8_t{0});
            }
        };

        if (j.contains("planes") && j["planes"].is_array() && j["planes"].size() >= 2) {
            desPlane(j["planes"][0], gs.planes[0]);
            desPlane(j["planes"][1], gs.planes[1]);
        }

        if (j.contains("bullets") && j["bullets"].is_array()) {
            for (const auto& bj : j["bullets"]) {
                BulletSnapshot b;
                b.x       = bj.value("x",   0.f);
                b.y       = bj.value("y",   0.f);
                b.dir     = bj.value("dir", 0.f);
                b.firedBy = bj.value("by",  uint8_t{0});
                gs.bullets.push_back(b);
            }
        }
        return gs;
    }
};
