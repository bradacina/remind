# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import timer
import os
import times

when isMainModule:
  var ts = newTimerSystem()
  
  #let timeFormat = initTimeFormat("HH:mm:ss'.'fff")

  var t1,t2,t3: Timer

  t1 = ts.newTimer(1000, true, proc()= 
    #echo "[", now().format(timeFormat), "]"
    echo "Timer 1, ", $t1
  )
  t2 = ts.newTimer(2000, true, proc() = echo "Timer 2, ", $t2)
  t3 = ts.newTimer(10000, false, proc() = t2.stop)

  while true:
    sleep(900)
    ts.update()
