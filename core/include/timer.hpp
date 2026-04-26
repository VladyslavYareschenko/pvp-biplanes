#pragma once

class Timer
{
    float mTimeout   {};
    float mCounter   {};
    bool  mIsCounting{};

public:
    explicit Timer(float timeout = 0.0f);

    void Update(float dt);

    void Start();
    void Stop();
    void Pause();
    void Continue();
    void Reset();

    void SetNewTimeout(float t);
    void SetNewRemainder(float r);

    float remainderTime() const;
    float timeout()       const;

    bool isReady()    const;
    bool isCounting() const;
};
