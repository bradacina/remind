import sequtils
import times
import tables

const MILLI_SLOT_SIZE = 100 # 100 millisecond slots
const SECOND_SLOT_SIZE = 1000 # 1000 millisecond slots
const MILLI_SLOTS = 10 # 10 slots in the wheel (ie. 1 second total)
const SECOND_SLOTS = 60 # 60 slots in the wheel (ie. 1 minute total)
const NANOSECONDS_IN_MILLIS = 1_000_000
const NANOS_IN_MILLIS_SLOT = NANOSECONDS_IN_MILLIS * MILLI_SLOT_SIZE

const MILLI_SLOTS_HIGH = MILLI_SLOTS - 1
const SECOND_SLOTS_HIGH = SECOND_SLOTS - 1

type
    TimerCallback = proc ()

    Timer* = ref object
        id: uint
        callback: TimerCallback
        isRepeating: bool
        timeout: int # in milliseconds
        timerSystem: TimerSystem
        isStopped: bool
        nextExecution: DateTime

    Slot = seq[Timer]

    TimerSystem = ref object
        millisecondsWheel: array[0..MILLI_SLOTS_HIGH, Slot] # 100ms slots
        secondsWheel: array[0..SECOND_SLOTS_HIGH, Slot] # 1 second slots
        overflowWheel: TableRef[uint, Timer]
        lastUpdate: DateTime
        lastMillisSlot: int

    Index = ref object
        second: uint8
        milli: uint8

var nextTimerId = 0u

proc newTimerId(): uint =
    nextTimerId.inc
    nextTimerId

let timeFormat = initTimeFormat("HH:mm:ss'.'fff")

proc `$`*(t: Timer): string =
    
    return "Timeout:" & $t.timeout &
                ", Repeating:" & $t.isRepeating &
                ", Stopped:" & $t.isStopped & 
                ", NextExecution:" & t.nextExecution.format(timeFormat)


proc printWheel(wheel: openArray[Slot]) =

    for idx, slot in wheel.pairs:
        echo "At index ", idx, "\n"
        for t in slot:
            echo t


proc scheduleTimer(ts:TimerSystem, t: Timer) =

    if t.isRepeating == true and t.timeout < MILLI_SLOT_SIZE:
        raise newException(ValueError, "Cannot repeat timers in less than 100 milliseconds")

    if t.timeout >= 60 * 1000:
        raise newException(ValueError, "Cannot schedule timers more than 60 seconds in the future")

    if ts.lastUpdate.minute != t.nextExecution.minute:
        ts.overflowWheel.add(t.id, t)

    elif ts.lastUpdate.second != t.nextExecution.second:
        ts.secondsWheel[t.nextExecution.second].add(t)

    else:
        ts.millisecondsWheel[t.nextExecution.nanosecond div NANOS_IN_MILLIS_SLOT].add(t)


proc setupMillisWheel(ts: TimerSystem, currentTime: DateTime) =
    
    for slots in ts.millisecondsWheel:
        assert slots.len == 0

    for timer in ts.secondsWheel[currentTime.second]:
        let milliSlot = timer.nextExecution.nanosecond div NANOS_IN_MILLIS_SLOT
        ts.millisecondsWheel[milliSlot].add(timer)

proc setupSecondsWheel(ts: TimerSystem) =
    for slots in ts.secondsWheel.mitems:
        let slotsLen = slots.len
        if slotsLen > 0:
            slots.delete(0, slotsLen-1)

    let nextMinute = ts.lastUpdate.minute + 1
    for id, timer in ts.overflowWheel:
        if timer.nextExecution.minute == nextMinute:
            ts.secondsWheel[timer.nextExecution.second].add(timer)

        ts.overflowWheel.del(id)

proc runMillisWheelSlot(ts: TimerSystem, slotNumber: int) =

    for timer in ts.millisecondsWheel[slotNumber]:
        if not timer.isStopped:
            timer.callback()
        else:
            continue

        if not timer.isRepeating:
            timer.isStopped = true
        else:
            timer.nextExecution = now() + milliseconds(timer.timeout)
            ts.scheduleTimer(timer)

    let len = ts.millisecondsWheel[slotNumber].len
    # clear the slot of all timers
    if len > 0:
        ts.millisecondsWheel[slotNumber].delete(0, len-1)


proc newTimerSystem*(): TimerSystem =

    let lastUpdate = now()
    let lastMillisSlot = lastUpdate.nanosecond div NANOS_IN_MILLIS_SLOT
    TimerSystem(
        lastUpdate: lastUpdate,
        lastMillisSlot: lastMillisSlot,
        overflowWheel: newTable[uint, Timer]())


proc newTimer*(ts: TimerSystem, timeout: int, isRepeating: bool = false, callback: TimerCallback): Timer =

    let localTime = now()
    let nextExecution = localTime + milliseconds(timeout)

    result = Timer(
        id: newTimerId(),
        callback: callback,
        isRepeating: isRepeating, 
        timeout: timeout, 
        timerSystem: ts,
        nextExecution: nextExecution)

    ts.scheduleTimer(result)


proc stop*(t: Timer) =

    t.isStopped = true


proc update*(ts: TimerSystem) =

    let currentTime = now()

    let duration = currentTime - ts.lastUpdate

    if duration.seconds > 1:
        echo "Warning: More than 1 second has passed between updates"

    if duration.nanoseconds div NANOSECONDS_IN_MILLIS > 150:
        echo "More than 150 ms have passed between updates"

    if currentTime.minute != ts.lastUpdate.minute:
        ts.setupSecondsWheel()

    # have we crossed the second boundary
    if currentTime.second != ts.lastUpdate.second:
        # catch up the rest of the last second
        if ts.lastMillisSlot != MILLI_SLOTS - 1:
            for slotNumber in ts.lastMillisSlot+1..<MILLI_SLOTS:
                ts.runMillisWheelSlot(slotNumber)

        ts.setupMillisWheel(currentTime)
        let currentMillisSlot = currentTime.nanosecond div NANOS_IN_MILLIS_SLOT

        #catch up the current second to current milliseconds
        for slotNumber in 0..currentMillisSlot:
            ts.runMillisWheelSlot(slotNumber)
        ts.lastUpdate = currentTime
        ts.lastMillisSlot = ts.lastUpdate.nanosecond div NANOS_IN_MILLIS_SLOT

        return
    
    let currentMillisSlot = currentTime.nanosecond div NANOS_IN_MILLIS_SLOT
    
    if currentMillisSlot == ts.lastMillisSlot:
        ts.lastUpdate = currentTime
        return

    for slotNumber in ts.lastMillisSlot+1..currentMillisSlot:
        ts.runMillisWheelSlot(slotNumber)

    ts.lastUpdate = currentTime
    ts.lastMillisSlot = currentMillisSlot

