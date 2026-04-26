#include <core/include/timer.hpp>

Timer::Timer(float timeout)
    : mTimeout{timeout}
    , mCounter{0.0f}
    , mIsCounting{false}
{}

void Timer::Update(float dt)
{
    if (!mIsCounting) return;

    if (mCounter > 0.0f) {
        mCounter -= dt;
        if (mCounter < 0.0f)
            mCounter = 0.0f;
    } else {
        Stop();
    }
}

void Timer::Start()
{
    mIsCounting = true;
    Reset();
}

void Timer::Stop()
{
    mIsCounting = false;
    mCounter    = 0.0f;
}

void Timer::Pause()
{
    mIsCounting = false;
}

void Timer::Continue()
{
    mIsCounting = true;
}

void Timer::Reset()
{
    mCounter = mTimeout;
}

void Timer::SetNewTimeout(float t)
{
    mTimeout = t;
}

void Timer::SetNewRemainder(float r)
{
    mCounter = r;
}

float Timer::remainderTime() const { return mCounter;    }
float Timer::timeout()       const { return mTimeout;    }
bool  Timer::isReady()       const { return mCounter <= 0.0f; }
bool  Timer::isCounting()    const { return mIsCounting; }
