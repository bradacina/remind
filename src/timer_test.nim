
import unittest
import times

proc now(): DateTime =
            return initDateTime(1, mJan, 1980, 20, 10, 30, 500_000_000)

include timer

suite "scheduleTimer":
    setup:
        let ts = newTimerSystem()

    test "cannot schedule in less than 100 milliseconds":
        var t = Timer(isRepeating: true, timeout: 99, nextExecution: now() + milliseconds(99))
        expect ValueError:
            ts.scheduleTimer(t)

    test "cannot schedule more than 60 seconds in advance":
        var t = Timer(timeout: 60001, nextExecution: now() + milliseconds(60001))

        expect ValueError:
            ts.scheduleTimer(t)

    test "in the next millisecond slot":
        var t = Timer(timeout: 100, nextExecution: now() + milliseconds(100))

        ts.scheduleTimer(t)
        check ts.millisecondsWheel[5].len == 0
        check ts.millisecondsWheel[6].len == 1
        check ts.millisecondsWheel[7].len == 0

    test "in the 2 next millisecond slot":
        var t1 = Timer(timeout: 100, nextExecution: now() + milliseconds(100))
        var t2 = Timer(timeout: 200, nextExecution: now() + milliseconds(200))

        ts.scheduleTimer(t1)
        ts.scheduleTimer(t2)
        check ts.millisecondsWheel[5].len == 0
        check ts.millisecondsWheel[6].len == 1
        check ts.millisecondsWheel[7].len == 1

    test "in the last millisecond slot":
        var t = Timer(timeout: 400, nextExecution: now() + milliseconds(400))

        ts.scheduleTimer(t)
        check ts.millisecondsWheel[7].len == 0
        check ts.millisecondsWheel[8].len == 0
        check ts.millisecondsWheel[9].len == 1

    test "in the next second slot when spanning the second":
        var t = Timer(timeout: 500, nextExecution: now() + milliseconds(500))
        ts.scheduleTimer(t)
        check ts.millisecondsWheel[8].len == 0
        check ts.millisecondsWheel[9].len == 0
        check ts.secondsWheel[31].len == 1

    test "in the next second slot":
        var t = Timer(timeout: 1000, nextExecution: now() + milliseconds(1000))

        ts.scheduleTimer(t)
        check ts.millisecondsWheel[0].len == 0
        check ts.millisecondsWheel[1].len == 0
        check ts.millisecondsWheel[2].len == 0
        check ts.millisecondsWheel[8].len == 0
        check ts.millisecondsWheel[9].len == 0
        check ts.secondsWheel[31].len == 1

    test "in the next 2 second slots":
        var t1 = Timer(timeout: 1000, nextExecution: now() + milliseconds(1000))
        var t2 = Timer(timeout: 2000, nextExecution: now() + milliseconds(2000))

        ts.scheduleTimer(t1)
        ts.scheduleTimer(t2)
        check ts.secondsWheel[31].len == 1
        check ts.secondsWheel[32].len == 1

    test "in the last 2 second slots":
        var t1 = Timer(timeout: 29499, nextExecution: now() + milliseconds(29499))
        var t2 = Timer(timeout: 28400, nextExecution: now() + milliseconds(28400))

        ts.scheduleTimer(t1)
        ts.scheduleTimer(t2)
        check ts.secondsWheel[58].len == 1
        check ts.secondsWheel[59].len == 1

    test "in the overflow slots":
        var t1 = Timer(timeout: 30000, nextExecution: now() + milliseconds(30000))
        var t2 = Timer(timeout: 50000, nextExecution: now() + milliseconds(50000))

        ts.scheduleTimer(t1)
        ts.scheduleTimer(t2)
        check ts.overflowWheel.len == 2