breed [trucks truck]
breed [containers container]
breed [cranes crane]
breed [clients client]

clients-own [
  my-type ; truck client type (1, 2, or 3)
  my-preference ; my preferred arrival time
  my-bound ; my time flexibility bound, cannot exceed (+ or -) this value
  my-ewt ; value of my expected wait time (global ewt * variance)
  my-wait-time ; actual wait time for this client
  my-est-cost ; my estimated total cost, calculated after serviced
  my-inc-cost ; my inconvenience cost, calculated after serviced

  my-arrival-time ; my final arriving time

  my-truck
  cargo
  my-start-time
  book?
  order
  overb?
]

containers-own [
  z-cor ;0..3, the z-coordinate of this container
  my-group ;my position
  my-stack ;my position
  my-row   ;my position
  my-truck ;the truck that wants me, or is carrying me
  my-crane
  my-block
  pick-me ; false if the container's truck is not in the stack yet
]

cranes-own [
  goal ; [#ticks-to-wait "goal-position" group stack] of the goal position for the crane, or ["deliver-containter" container-who], or []
  travel-distance ; monitor distance traveled by crane
  my-block
  crane-idle
  crane-service
  state?
  t-gantry ; ticks needed for current gantry operation saved here
  t-liftnl ; ticks needed for current lift without load operation saved here
  t-liftl ; ticks needed for current lift with load operation saved here
  t-gantry-back ; ticks needed for current gantry operation to the truck
  gantry-position ; location of the gantry in the row (ycor)
]

trucks-own [
  cargo ; the container that I want to get
  my-group
  my-stack
  my-start-time ; creation time of each truck
  waiting ; true if I am waiting outside the port, waiting to get in because there is another truck in my stack
  current-idle ; current time spent idling (waiting to be serviced in the stack)
  my-crane ; crane that will pick me
  my-utility ; my utility
  on-service ; truck is on service True/False
  service-time ; starting ticks when truck is being serviced
  my-block
  my-terminal-time ; starting ticks when truck is inside terminal
  my-queue-time ; total time trucks outside terminal queueing
  my-client
  book?
  my-arrival-time ; the time he booked slot for
]

;ticks: each tick is one second
globals [
  crane-road-xcors ; list of the x-coordinates where the crane road travels N<->S
  crane-road-ycors ; list of the y-coordinates where the crane road travels E<->W
  num-trucks-serviced ; total number of trucks served
  total-wait-time ; total wait time of all trucks that have been served
  decommitment-penalty ;
  ticks-to-rehandle
  ticks-to-deliver
  ticks-to-move
  idle-time
  num-trucks-idling
  total-reshuffle ; total reshuffling activity
  total-reshuffle-time ; total reshuffling time
  total-service-time
  block-1-occupation
  block-2-occupation
  block-3-occupation
  block-4-occupation
  trucks-from-queue
  total-terminal-time
  total-queue-time
  postponed-request
  block-1-cargo
  block-2-cargo
  block-3-cargo
  block-4-cargo
  sessions
  total-app-time
  num-app-serviced
  current-no-shows
  num-no-shows
  current-interval
  globals-order
  spillover
  spillover-app
  spillover-walkin
  stack-list
  total-appointment-wt
  total-walkin-wt
  total-appointment-st
  total-walkin-st
  total-appointment-qt
  total-walkin-qt
  total-actual-bookings
  num-trucks-serviced-session

  total-truck-co2-global
  total-crane-co2-global
  total-truck-co-global
  total-crane-co-global
  total-truck-nox-global
  total-crane-nox-global
  total-truck-pm-global
  total-crane-pm-global
  total-truck-thc-global
  total-crane-thc-global

; globals for crane movement
  ticks-to-lift

; emission constant, please convert to (gram / second)
  truck-idle-co2
  truck-idle-n2o
  truck-idle-ch4
  truck-idle-pm10
  truck-idle-pm25
  truck-idle-dpm
  truck-idle-nox
  truck-idle-sox
  truck-idle-co
  truck-idle-hc

  crane-idle-co2
  crane-gantry-co2
  crane-trolleynoload-co2
  crane-trolleyload-co2
  crane-liftnoload-co2
  crane-liftload-co2

  crane-idle-co
  crane-gantry-co
  crane-trolleynoload-co
  crane-trolleyload-co
  crane-liftnoload-co
  crane-liftload-co

  crane-idle-nox
  crane-gantry-nox
  crane-trolleynoload-nox
  crane-trolleyload-nox
  crane-liftnoload-nox
  crane-liftload-nox

  crane-idle-thc
  crane-gantry-thc
  crane-trolleynoload-thc
  crane-trolleyload-thc
  crane-liftnoload-thc
  crane-liftload-thc

  crane-idle-pm
  crane-gantry-pm
  crane-trolleynoload-pm
  crane-trolleyload-pm
  crane-liftnoload-pm
  crane-liftload-pm

  ;inconvinience cost globals
  tc-1-cost
  tc-2-cost
  tc-3-cost

  tc-1-inc
  tc-2-inc
  tc-3-inc

  tc-1-serviced
  tc-2-serviced
  tc-3-serviced

  ;turn time estimation globals
  current-estimation
  current-ewt
]

to setup
  clear-all
  reset-ticks
  init-globals
  init-world
  init-crane
  init-container
;  init-client
end

to go
  ; check session
;  let list-session (list 0 3600 7200 10800 14400 18000 21600 25200 28800 32400)
  let list-session (list 0 3601 7201 10801 14401 18001 21601 25201 28801 32401)
  if ticks >= 36000 [ ; stop after 10 hour
    count-spillover ; count for the last session (tick 36000)
    stop
  ]

  if (member? ticks list-session) [
    set sessions sessions + 1
    count-spillover
    set num-trucks-serviced-session 0
;    if run? = true [
      init-container
      init-client
      do-appointment
;    ]
  ]

  do-walk-in
  do-arrive
  appointment-arrival
  do-move

  appointment-error-check ; bug fix

  ask cranes [go-crane]
  tick

end

to do-move
  ; count truck threshold inside terminal
  let tlane list 0 0
  let wlane (list 8 9 10 11 12) ; list of ycor that
  let ntruck count trucks with [member? ycor tlane]

  ifelse ignore-slot? = true [
    set ntruck 0 ; do nothing
    ][
    if ntruck >= slot-per-session [stop] ; set the threshold for trucks allowed inside based on slot per sessions
  ]

  ; choose the truck to be let inside
  let booked-truck count trucks with [member? ycor wlane and book? = true] ; count trucks in the wait lane (dark grey area)
  let the-truck 0

  ; sequence 1
  if sequencing = "random" [ ; randomly let any trucks
    set the-truck one-of trucks with [waiting = false and my-crane = nobody]
  ]

  ; sequence 2
  if sequencing = "loose-appointment" [ ; let the one with appointment first, then the walk ins for the remaining slots
    ifelse booked-truck > 0 [
      set the-truck one-of trucks with [waiting = false and my-crane = nobody and book? = true]
    ][
;      ifelse current-interval = interval [ ; use interval delay, adjusted in do-arrive procedure
      set the-truck one-of trucks with [waiting = false and my-crane = nobody]
;      ]
;      [stop]
    ]
  ]

  ; sequence 3
  if sequencing = "strict-appointment" [ ; let only appointment truck first, then the walk ins only if no appointment trucks inside
    let booked-truck-inside count trucks with [member? ycor tlane and book? = true]
    ifelse booked-truck-inside = 0 [
      set the-truck one-of trucks with [waiting = false and my-crane = nobody]
    ][
      set the-truck one-of trucks with [waiting = false and my-crane = nobody and book? = true]
  ]
  ]

  ; sequence 4
  if sequencing = "free" [
    set the-truck min-one-of trucks with [waiting = false and my-crane = nobody] [my-arrival-time]
  ]


  ; move
  if the-truck = nobody [stop]
  ask the-truck [
    if cargo = nobody [stop]
    goto-container
    stack-slot-check ; check if there is already truck in the destination
  ]

end

to init-globals
  set ticks-to-lift 15 ; base number of crane lifting procedure
  set ticks-to-rehandle 40 ; number of ticks it takes for crane to move container from one place to another in the same stack.
  set ticks-to-deliver 50 ;number of ticks it takes for crane to move container from stack to truck
  set ticks-to-move 6 ;number of ticks it takes for the crane to move to an adjacent container
  set decommitment-penalty 1000
  set crane-road-xcors (list 0 8 9 10 11 12)
  set crane-road-ycors (list 0 41)

; emission constants  in g/sec
set truck-idle-co2 1.28888888888889
set truck-idle-n2o 1.02777777777778E-05
set truck-idle-ch4 0.00005
set truck-idle-pm10 6.11111111111111E-05
set truck-idle-pm25 5.55555555555556E-05
set truck-idle-dpm 5.55555555555556E-05
set truck-idle-nox 0.0263333333333333
set truck-idle-sox 1.11111111111111E-05
set truck-idle-co 0.00467222222222222
set truck-idle-hc 0.00173333333333333

set crane-idle-co2 1.22805555555556
set crane-gantry-co2 0.214166666666667
set crane-trolleynoload-co2 0.145277777777778
set crane-trolleyload-co2 0.15
set crane-liftnoload-co2 0.438611111111111
set crane-liftload-co2 0.279444444444444

set crane-idle-co 0.354722222222222
set crane-gantry-co 0.431388888888889
set crane-trolleynoload-co 0.391666666666667
set crane-trolleyload-co 0.410277777777778
set crane-liftnoload-co 0.470277777777778
set crane-liftload-co 0.847222222222222

set crane-idle-nox 0.725555555555556
set crane-gantry-nox 1.40194444444444
set crane-trolleynoload-nox 0.936944444444444
set crane-trolleyload-nox 0.983333333333333
set crane-liftnoload-nox 1.92
set crane-liftload-nox 2.71111111111111

set crane-idle-thc 0.0916666666666667
set crane-gantry-thc 0.120833333333333
set crane-trolleynoload-thc 0.106666666666667
set crane-trolleyload-thc 0.101388888888889
set crane-liftnoload-thc 0.135833333333333
set crane-liftload-thc 0.161944444444444

set crane-idle-pm 0.0594444444444444
set crane-gantry-pm 0.0741666666666667
set crane-trolleynoload-pm 0.0466666666666667
set crane-trolleyload-pm 0.0513888888888889
set crane-liftnoload-pm 0.0769444444444444
set crane-liftload-pm 0.131666666666667
end

to init-world
  ask patches with [pycor = 0 or pycor = 7] [ set pcolor gray ]
  ask patches with [pycor > 0 and pycor < 7] [set pcolor white]
  ask patches with [pycor > 7 and pycor < 13] [set pcolor 6.7]
  ask patches with [pycor > 12] [set pcolor 7.7]
end

to init-container
  let amt 300
;  let n-cont 0
  let n-cont count containers
  let buffer max list 0 (amt - n-cont)
;  create-containers 100 [
  create-containers buffer [
    set z-cor 0
    set shape "square"
    set color black
    set size .6
    set my-truck nobody
    set my-crane nobody
    set pick-me false
    find-random-empty-position
;    let my-x random 41;
;    let my-y (random 6) + 1
;    setxy my-x my-y
  ]
end

to init-crane
  create-cranes 1 [
    set shape "arrow"
    set color white
    set heading 90
    set goal []
    set-my-position position-in-yard 0 0 -1
    set state? "idle"
    set gantry-position 6 ; set default gantry position in 6 ycor)
  ]
end

to init-client
  ;uncomment to use buffer mode
  ;count current clients, tc means truck company
  ;let n-tc-1 count clients with [my-type = 1]
  ;let n-tc-2 count clients with [my-type = 2]
  ;let n-tc-3 count clients with [my-type = 3]

  ;uncomment to use fixed truck per hour rate mode
  let n-tc-1 0
  let n-tc-2 0
  let n-tc-3 0

  ;find the differences, or buffer amount, cannot be negative
  let tc-1-buffer max list 0 (n-for-each-tc - n-tc-1)
  let tc-2-buffer max list 0 (n-for-each-tc - n-tc-2)
  let tc-3-buffer max list 0 (n-for-each-tc - n-tc-3)

  ;create client based on amount defined
  create-the-client 1 tc-1-buffer
  create-the-client 2 tc-2-buffer
  create-the-client 3 tc-3-buffer

end

to create-the-client [tc-type amount]; function to create clients
  ask n-of amount patches with [ pycor > 12 and not any? clients-here][
    sprout-clients 1 [
      set shape "person"
      set my-type tc-type
      if my-type = 1 [set color 15]
      if my-type = 2 [set color 25]
      if my-type = 3 [set color 35]
      set cargo nobody
      set my-truck nobody
      set book? 0 ; as an indicator of a new client

      set my-preference (random 3600) + ticks; my preferred arrival time
      set my-arrival-time my-preference
      set my-bound list (-1 * tc-1-bound) (1 * tc-1-bound) ; my time flexibility bound, cannot exceed (+ or -) this value
      ;set my-ewt trucks-ewt * ((one-of[1 -1]*(random-float trucks-ewt-variance)) + 1); value of my expected wait time (global ewt * variance)
    ]
  ]
end

to do-appointment ; appointments are made in each beginning of sessions
  set current-ewt 0 ; reset current expected wait time
  set current-estimation avg-both-ta ; reset current estimation in each beginning of sessions
  set stack-list [] ; a list of stack that has been booked, reset every new session
;  let set-arrival-time round (3600 / slot-per-session) ; 1 hour per slot per session
  let x 1
  let new-appointment count clients with [book? = 0]
  repeat new-appointment [
    ;let the-client one-of clients with [book? = 0]
    let the-client min-one-of clients with [book? = 0] [my-preference]
    if (the-client = nobody) [stop]

    ;function to choose only cargo that is not on stack-list
    let the-cargo one-of containers with [my-truck = nobody and pick-me = false and not member? my-stack stack-list]
    let chosen-stack [my-stack] of the-cargo

    if (the-cargo = nobody) [stop]
    ask the-client [

      set my-ewt avg-both-ta * ((one-of[1 -1]*(random-float trucks-ewt-variance)) + 1); value of my expected wait time (global ewt * variance)

      set book? true
      set my-start-time ticks
;      set color green
      set cargo the-cargo
      if (cargo = nobody) [die stop] ; all stacks are full!!
      ask cargo [
        ; set color appointment
        set color green
        set size 1
        ]
      set my-truck nobody
;      set my-arrival-time (set-arrival-time * x) + ticks

      ;update the stack-list
;      set stack-list fput [my-stack] of cargo stack-list

  if negotiation? = true [
        negotiate-function x
    ]

    ]
;=======================================================================
  ; overbooking model, where for every slot there is probability (p = estimated no shows) to allow new bookings
;    if overbook? = true [
;      let ob-client one-of clients with [cargo = nobody and book? = 0]
;      if (ob-client = nobody) [stop]
;      let ob-cargo one-of containers with [my-truck = nobody and pick-me = false and my-stack = chosen-stack]
;      ifelse random-float 1.0 < no-shows [
;        ask ob-client [
;          set book? true
;          set my-start-time ticks
;          set color green
;          set cargo ob-cargo
;          if (cargo = nobody) [die stop] ; all stacks are full!
;          ask cargo [
;            ; set color appointment
;            set color green
;            set size 1
;          ]
;          set my-truck nobody
;          set my-arrival-time (set-arrival-time * x ) + ticks + 1 ; trucks will arrive 1 sec later
;          set overb? true
;        ]
;        print "overbook occur"
;      ][
;        print "overbook does not occur"
;        ]
;    ]
;    print x
;=======================================================================

  set x x + 1
  ]
  ;recap actual bookings (booking + overbooking)
  set total-actual-bookings count clients with [overb? = true] + slot-per-session
end

to do-walk-in ; walk ins are generated each interval (second),
  ifelse current-interval = interval [
    let the-client one-of clients with [cargo = nobody]
    if (the-client = nobody) [stop]
    let the-cargo one-of containers with [my-truck = nobody and pick-me = false]
    if random-float 1.0 < walk-ins [
      ask the-client [
;        if (cargo = nobody) [die stop] ; all stacks are full!!
        set book? false
        set my-start-time ticks
;        set color yellow
        set cargo the-cargo
        ask cargo [
          ; set color walk in
;          set color yellow
          set size 1]
        set my-truck nobody
      ]
    ]
    set current-interval 0
  ][
  set current-interval current-interval + 1
  ]
end

to do-arrive ;ask a client to create his/her truck
  let the-client one-of clients with [cargo != nobody and my-truck = nobody]
  ifelse (the-client = nobody) [stop][

      if ([book?] of the-client = true)[stop] ; booking trucks are not created here

      create-the-truck the-client
  ]
end

to appointment-arrival ; procedure for appointment arrival, with a chance of no-show
  let the-client one-of clients with [my-arrival-time = ticks and cargo != nobody]
  ifelse the-client != nobody [
  ifelse random-float 1.0 < no-shows [

;    ifelse ob-forced-show? = true [ ; force show the overbook
;        if [overb?] of the-client = true [
;          create-the-truck the-client
;        ]
;      ][

    ; usual no shows
    ask the-client [
      if book? = true [ ; does not count walk in no shows
        set num-no-shows num-no-shows + 1
      ]
      ask cargo [
        set color red
        set size .6
        set my-truck nobody
      ]
      die
    ]

  ][
      create-the-truck the-client
  ]
  ][
    stop
  ]

end

; function to create client's truck
to create-the-truck [the-client]
      create-trucks 1 [
      let my-x random max-pxcor
      let my-y (random 5) + 8
      setxy my-x my-y
      set shape "truck"
      set waiting false
      set my-start-time ticks
      set my-crane nobody ; no crane booked this truck yet
      set on-service false ; set on-service false at first
      set cargo [cargo] of the-client
      ask cargo [set my-truck myself]
      set book? [book?] of the-client

      ; appointment function
      ifelse book? = true [
          set color green
        ][
          set color yellow
        ]

      set my-group [my-group] of cargo
      set my-stack [my-stack] of cargo
      set my-client the-client
      ask the-client [set my-truck myself]
    ]
end

to negotiate-function [x]
  ;calculate time boundaries
  let lower-bound max list ticks ((item 0 my-bound) + my-preference)
  let upper-bound min list 36000 ((item 1 my-bound) + my-preference)
  set my-bound list lower-bound upper-bound

  ;calculate the ideal time to move
  let new-time current-estimation - my-ewt

  ;function test: do not move appointment time if estimation is below the expected
  ;if new-time < 1 [set new-time 0]

  ;avoid exceeding the time bound
  if ticks < 3600 [set new-time 0] ; disregard first tick

  ;move arrival time
  set my-arrival-time round max list ticks (my-arrival-time + new-time) ; avoid moving to past ticks

  ;avoid exceeding the time bound
  if my-arrival-time < lower-bound [set my-arrival-time lower-bound]
  if my-arrival-time > upper-bound [set my-arrival-time upper-bound]

  ;update turn time estimation prediction
  set current-ewt current-ewt + my-ewt
  set current-estimation (total-appointment-wt + current-ewt) / (num-trucks-serviced + x)

  if new-time > 0 [set color blue] ;blue if truck delays its time
  if new-time < 0 [set color yellow] ;yellow if truck advances its time
end

to appointment-error-check
  let x count clients with [book? = true and cargo = nobody]
  if x > 0 [
    ask clients with [book? = true and cargo = nobody] [
      if my-truck = nobody [stop]
      ask my-truck [die]
      die
    ]
    ask trucks with [waiting = true and cargo = nobody][
      die
    ]
  ]
end

to count-spillover
  set spillover count trucks with [member? ycor list 0 0] ; count trucks that is not serviced from previous session (all)
  set spillover-app count trucks with [member? ycor list 0 0 and book? = true] ; count trucks that is not serviced from previous session (appointment)
  set spillover-walkin spillover - spillover-app ; (walkin)
end

to estimate-cost [tc-type] ; cost estimation function in the truck function
  ; function to estimate the cost. alpha = constant for waiting time. beta = constant for inconvenience of moving arrival time. negative value is a surplus.
  ; old function
  ; set my-est-cost (alpha * (my-wait-time - my-ewt)) + (beta * (abs(my-preference - my-arrival-time)))

  ; new function = waiting cost + inconvenience cost
  set my-est-cost (alpha * my-wait-time) + (beta * (abs(my-preference - my-arrival-time)))

  ; set inconvenience cost only
  set my-inc-cost beta * (abs(my-preference - my-arrival-time))

  if tc-type = 1 [set tc-1-cost tc-1-cost + my-est-cost]
  if tc-type = 2 [set tc-2-cost tc-2-cost + my-est-cost]
  if tc-type = 3 [set tc-3-cost tc-3-cost + my-est-cost]

  if tc-type = 1 [set tc-1-inc tc-1-inc + my-inc-cost]
  if tc-type = 2 [set tc-2-inc tc-2-inc + my-inc-cost]
  if tc-type = 3 [set tc-3-inc tc-3-inc + my-inc-cost]
end

;;;;;;;;;;;; REPORTERS

to-report avg-est-cost-1
  if tc-1-serviced = 0 [report 0]
  report tc-1-cost / tc-1-serviced
end

to-report avg-est-cost-2
  if tc-2-serviced = 0 [report 0]
  report tc-2-cost / tc-2-serviced
end

to-report avg-est-cost-3
  if tc-3-serviced = 0 [report 0]
  report tc-3-cost / tc-3-serviced
end

to-report avg-est-cost-all
  if num-trucks-serviced = 0 [report 0]
  report (tc-1-cost + tc-2-cost + tc-3-cost) / num-trucks-serviced
end

;;;;;;;;;;;;;

to-report avg-inc-cost-1
  if tc-1-serviced = 0 [report 0]
  report tc-1-inc / tc-1-serviced
end

to-report avg-inc-cost-2
  if tc-2-serviced = 0 [report 0]
  report tc-2-inc / tc-2-serviced
end

to-report avg-inc-cost-3
  if tc-3-serviced = 0 [report 0]
  report tc-3-inc / tc-3-serviced
end

to-report avg-inc-cost-all
  if num-trucks-serviced = 0 [report 0]
  report (tc-1-inc + tc-2-inc + tc-3-inc) / num-trucks-serviced
end

;;;;;;;;;;;;;

to-report crane-utilization
  if ticks = 0 [report 0]
  let the-crane one-of cranes
  let cidle [crane-idle] of the-crane
  report 1 - cidle / ticks
end

to-report avg-wait-time
  if num-trucks-serviced = 0 [report 0]
  report total-wait-time / num-trucks-serviced
end

to-report avg-app-time
  if num-app-serviced = 0 [report 0]
  report total-app-time / num-app-serviced
end

to-report actual-no-show-rate; only count normal appointment without overbooking
  let x sessions + 1
  if x < 1 [report 0]
  report num-no-shows / (x * slot-per-session)
end

; wt = wait time, time from truck creation to die
; st = service time, time from crane chose a truck to die
; qt = queue time, time from truck creation to service time

to-report avg-walkin-wt
  let x max list 0 (num-trucks-serviced - num-app-serviced)
  if x = 0 [report 0]
  report total-walkin-wt / x
end

to-report avg-appointment-wt
  let x max list 0 num-app-serviced
  if x = 0 [report 0]
  report total-appointment-wt / x
end

to-report avg-both-ta
  let x num-trucks-serviced
  if x = 0 [report 0]
  report (total-walkin-wt + total-appointment-wt) / x
end

;;;;;;;;;

to-report avg-appointment-st
  let x max list 0 num-app-serviced
  if x = 0 [report 0]
  report total-appointment-st / x
end

to-report avg-walkin-st
  let x max list 0 (num-trucks-serviced - num-app-serviced)
  if x = 0 [report 0]
  report total-walkin-st / x
end

to-report avg-both-st
  let x num-trucks-serviced
  if x = 0 [report 0]
  report (total-walkin-st + total-appointment-st) / x
end

;;;;;;;;;

to-report avg-appointment-qt
  let x max list 0 num-app-serviced
  if x = 0 [report 0]
  report total-appointment-qt / x
end

to-report avg-walkin-qt
  let x max list 0 (num-trucks-serviced - num-app-serviced)
  if x = 0 [report 0]
  report total-walkin-qt / x
end

to-report avg-both-qt
  let x num-trucks-serviced
  if x = 0 [report 0]
  report (total-walkin-qt + total-appointment-qt) / x
end

;;;;;;;;;;;;;;;;;
;;;;;;;;; emission reporters, only for single crane problem
;;;;;;;;;;;;;;;;;

to-report crane-emission-activity-co2
  let x one-of cranes
  if x = nobody [report 0]
  let y [state?] of x
  if y = "idle" [ ; report idling emission
    report crane-idle-co2
  ]
  if y = "travel" [ ; report traveling emission
    report crane-trolleynoload-co2
  ]
  if y = "reshuffle" [
    report crane-liftnoload-co2
  ]
  if y = "gantry" [
    report crane-gantry-co2
  ]
  if y = "lift-load" [
    report crane-liftload-co2
  ]
  if y = "lift-no-load" [
    report crane-liftnoload-co2
  ]
end

to-report total-crane-co2
  let x ticks
  if x = 0 [report total-crane-co2-global]
  let this-tick crane-emission-activity-co2
  set total-crane-co2-global total-crane-co2-global + this-tick
  report total-crane-co2-global
end

to-report truck-emission-activity-co2
  let x count trucks
  if x = nobody [report 0]
  report x * truck-idle-co2
end

to-report total-truck-co2
  let x count trucks
  if x = 0 [report total-truck-co2-global]
  let this-tick x * truck-idle-co2
  set total-truck-co2-global total-truck-co2-global + this-tick
  report total-truck-co2-global
end

to-report both-co2
  report total-crane-co2 + total-truck-co2
end

to-report both-co2-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report (total-crane-co2 + total-truck-co2) / x
end

to-report truck-co2-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report total-truck-co2-global / x
end

to-report crane-co2-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report total-crane-co2-global / x
end
;;;;;;;;;;;;;;;;;;;;

to-report crane-emission-activity-co
  let x one-of cranes
  if x = nobody [report 0]
  let y [state?] of x
  if y = "idle" [ ; report idling emission
    report crane-idle-co
  ]
  if y = "travel" [ ; report traveling emission
    report crane-trolleynoload-co
  ]
  if y = "reshuffle" [
    report crane-liftnoload-co
  ]
  if y = "gantry" [
    report crane-gantry-co
  ]
  if y = "lift-load" [
    report crane-liftload-co
  ]
  if y = "lift-no-load" [
    report crane-liftnoload-co
  ]
end

to-report total-crane-co
  let x ticks
  if x = 0 [report total-crane-co-global]
  let this-tick crane-emission-activity-co
  set total-crane-co-global total-crane-co-global + this-tick
  report total-crane-co-global
end

to-report truck-emission-activity-co
  let x count trucks
  if x = nobody [report 0]
  report x * truck-idle-co
end

to-report total-truck-co
  let x count trucks
  if x = 0 [report total-truck-co-global]
  let this-tick x * truck-idle-co
  set total-truck-co-global total-truck-co-global + this-tick
  report total-truck-co-global
end

to-report both-co
  report total-crane-co + total-truck-co
end

to-report both-co-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report both-co / x
end

;;;;;;;;;;;;;;;;;;;;

to-report crane-emission-activity-nox
  let x one-of cranes
  if x = nobody [report 0]
  let y [state?] of x
  if y = "idle" [ ; report idling emission
    report crane-idle-nox
  ]
  if y = "travel" [ ; report traveling emission
    report crane-trolleynoload-nox
  ]
  if y = "reshuffle" [
    report crane-liftnoload-nox
  ]
  if y = "gantry" [
    report crane-gantry-nox
  ]
  if y = "lift-load" [
    report crane-liftload-nox
  ]
  if y = "lift-no-load" [
    report crane-liftnoload-nox
  ]
end

to-report total-crane-nox
  let x ticks
  if x = 0 [report total-crane-nox-global]
  let this-tick crane-emission-activity-nox
  set total-crane-nox-global total-crane-nox-global + this-tick
  report total-crane-nox-global
end

to-report truck-emission-activity-nox
  let x count trucks
  if x = nobody [report 0]
  report x * truck-idle-nox
end

to-report total-truck-nox
  let x count trucks
  if x = 0 [report total-truck-nox-global]
  let this-tick x * truck-idle-nox
  set total-truck-nox-global total-truck-nox-global + this-tick
  report total-truck-nox-global
end

to-report both-nox
  report total-crane-nox + total-truck-nox
end

to-report both-nox-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report (total-crane-nox + total-truck-nox) / x
end

to-report truck-nox-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report total-truck-nox-global / x
end

to-report crane-nox-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report total-crane-nox-global / x
end

;;;;;;;;;;;;;;;;;;;;

to-report crane-emission-activity-pm
  let x one-of cranes
  if x = nobody [report 0]
  let y [state?] of x
  if y = "idle" [ ; report idling emission
    report crane-idle-pm
  ]
  if y = "travel" [ ; report traveling emission
    report crane-trolleynoload-pm
  ]
  if y = "reshuffle" [
    report crane-liftnoload-pm
  ]
  if y = "gantry" [
    report crane-gantry-pm
  ]
  if y = "lift-load" [
    report crane-liftload-pm
  ]
  if y = "lift-no-load" [
    report crane-liftnoload-pm
  ]
end

to-report total-crane-pm
  let x ticks
  if x = 0 [report total-crane-pm-global]
  let this-tick crane-emission-activity-pm
  set total-crane-pm-global total-crane-pm-global + this-tick
  report total-crane-pm-global
end

to-report truck-emission-activity-pm
  let x count trucks
  if x = nobody [report 0]
  report x * truck-idle-dpm
end

to-report total-truck-pm
  let x count trucks
  if x = 0 [report total-truck-pm-global]
  let this-tick x * truck-idle-dpm
  set total-truck-pm-global total-truck-pm-global + this-tick
  report total-truck-pm-global
end

to-report both-pm
  report total-crane-pm + total-truck-pm
end

to-report both-pm-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report both-pm / x
end

;;;;;;;;;;;;;;;;;;;;

to-report crane-emission-activity-thc
  let x one-of cranes
  if x = nobody [report 0]
  let y [state?] of x
  if y = "idle" [ ; report idling emission
    report crane-idle-thc
  ]
  if y = "travel" [ ; report traveling emission
    report crane-trolleynoload-thc
  ]
  if y = "reshuffle" [
    report crane-liftnoload-thc
  ]
  if y = "gantry" [
    report crane-gantry-thc
  ]
  if y = "lift-load" [
    report crane-liftload-thc
  ]
  if y = "lift-no-load" [
    report crane-liftnoload-thc
  ]
end

to-report total-crane-thc
  let x ticks
  if x = 0 [report total-crane-thc-global]
  let this-tick crane-emission-activity-thc
  set total-crane-thc-global total-crane-thc-global + this-tick
  report total-crane-thc-global
end

to-report truck-emission-activity-thc
  let x count trucks
  if x = nobody [report 0]
  report x * truck-idle-hc
end

to-report total-truck-thc
  let x count trucks
  if x = 0 [report total-truck-thc-global]
  let this-tick x * truck-idle-hc
  set total-truck-thc-global total-truck-thc-global + this-tick
  report total-truck-thc-global
end

to-report both-thc
  report total-crane-thc + total-truck-thc
end

to-report both-thc-avg
  let x num-trucks-serviced
  if x = 0 [report 0]
  report both-thc / x
end

;;;;;;;;;;;;;;;;;;;;

to-report queue-length
  let queue-ycor (list 7 8 9 10 11 12)
  report count trucks with [member? ycor queue-ycor]
end
;;;;;;;;;;;;;


to find-random-empty-position
  loop [
    set my-group random 0 ;a group is the set of 40 stacks
    set my-stack random 40;
    set my-row random 6
    set-my-position (position-in-yard my-group my-stack my-row)
    let others-here other turtles-here
    if ((not any? others-here) or count other turtles-here < 4)[ ;position works, put me here
      ifelse (not any? others-here)[
        set z-cor 0
      ][
        set z-cor 1 + max [z-cor] of other containers-here
      ]
      stop
    ]
  ]
end

to set-my-position [position-vector]
  setxy (item 0 position-vector) (item 1 position-vector)
end

to-report position-in-yard [group stack row]
  let y-pos int (group / 2)
  ifelse (y-pos = 0) [
    set y-pos 6
   ][
    set y-pos 6
  ]
  set y-pos (y-pos - row)
  let x-pos ((group mod 2) * 41 + 1) + stack
  report list x-pos y-pos
end

;===========================================================
;truck functions

;move the truck to the position where it can pick up cargo (container)
to goto-container
  setxy ([xcor] of cargo) ([ycor] of cargo)
  set ycor (ycor - (6 - [my-row] of cargo))
  ;set label my-start-time
  ask cargo [set pick-me true]
  set my-terminal-time ticks
  set my-queue-time my-terminal-time - my-start-time
end

;return an agentset of all the containers in the stack above me
to-report containers-in-stack
  report (turtle-set containers-at 0 1 containers-at 0 2 containers-at 0 3 containers-at 0 4 containers-at 0 5 containers-at 0 6)
end

to-report path-to-crane [the-crane]
  report [path-to-truck myself] of the-crane
end

to-report distance-to-crane [the-crane]
  report [distance-to-truck myself] of the-crane
end

to-report group-stack
  report (list my-group my-stack)
end

to stack-slot-check ; check if there is already truck in the destination
    if (any? other trucks-here) [ ;someone is already here, go to the waiting spot
;     setxy 0 16 ; default truck waiting location outside the terminal
      set waiting true
      setxy 0 7
      set color red ; color red to indicate its stack is occupied
    ]
end

;========================================
;crane functions

;Gets called at every tick, makes the crane do what it needs to do.
;An opportunistic crane will re-evaluate its goal-position goal at every tick
;A non opportunistic crane picks a goal-position and sticks to it until it delivers the container to that truck.
to go-crane
  if (not empty? goal and item 0 goal != 0)[ ;not time yet, countdown
    set goal replace-item 0 goal (item 0 goal - 1)
    stop  ]

  if (empty? goal or (opportunistic? and item 1 goal = "goal-position")) [;no goal position or opportunistic, set new goal
    ifelse (any? trucks with [not waiting])[
      let goalp []
      ;;;;;; =============== crane choice of utility function starts =================
      if (crane-pick-goal-function = "FCFS") [set goalp pick-goal-position-fcfo]
      if (crane-pick-goal-function = "distance") [set goalp pick-goal-position-distance]
      ;;;;;;; ================= crane choice of utility function ends =======================
      ifelse (goalp != nobody) [ ; if a valid group and stack values are returned
        set goal (sentence ticks-to-move "goal-position" item 0 goalp item 1 goalp)
      ][
        set goal [] ; reset goal
        set crane-idle crane-idle + 1
        set state? "idle"
        stop ; crane stay put until next tick
      ]
    ][
      set crane-idle crane-idle + 1
      set state? "idle"
      stop
    ]
  ]

;==================================================
  if (item 1 goal = "goal-position") [ ;move towards goal-position
    set travel-distance travel-distance + 1 ; travel distance of the crane + 1
    set state? "travel"
    let goal-position-xy position-in-yard (item 2 goal) (item 3 goal) -1
    goto-position (item 2 goal) (item 3 goal)
    if (not any? trucks-on (patch (item 0 goal-position-xy) (item 1 goal-position-xy - 7))) [ ;if there is no truck at the goal then reset goal
        set goal []
        set state? "idle"
        stop
    ]
    if (item 0 goal-position-xy = xcor and item 1 goal-position-xy = ycor) [;we are at the goal, next time deliver container
      let the-truck trucks-in-this-stack
      set crane-service crane-service + 1
      set state? "gantry"
;     set state? "service"

    ;;;;;; this only calculate service time when crane arrived in the trucks' stack, resulting a static service time
;    ask the-truck [
;    set on-service true
;    set service-time ticks] ; set on-service on truck true
;;;;;;;;
; USE DEFAULT TICKS TO DELIVER
;      set goal (list ticks-to-deliver "deliver-container" (item 0 [cargo] of the-truck))

;================================================== DEFINE TICKS
      ; define ticks needed for picking up container, and save it on the crane
      let target-container (item 0 [cargo] of the-truck)
      let target-gantry [ycor] of target-container
      let ticks-gantry-to-container abs(gantry-position - target-gantry) ; ticks from current position to target row
      let ticks-gantry-to-truck abs(1 - target-gantry) ; ticks from target row to truck row (1 ycor)
      let ticks-gantry-total ticks-gantry-to-container + ticks-gantry-to-truck

;      set t-gantry abs (-7 + [ycor] of target-container)
      set t-gantry ticks-gantry-total
      set t-liftnl ticks-to-lift + 5 * abs(-4 + [z-cor] of target-container)
      set t-liftl ticks-to-lift + 5 * abs(-4 + [z-cor] of target-container)

      set goal (list t-gantry "gantry" target-container)

    ]
    stop
  ]

;================================================== GANTRY PROCESS
  if (item 1 goal = "gantry") [
    ifelse (item 0 goal != 0) [
      set state? "gantry"
      set goal replace-item 0 goal (item 0 goal - 1)
  ][
      set goal replace-item 0 goal t-liftnl
      set goal replace-item 1 goal "lift-no-load"
    ]
  ]

;================================================== LIFT WITHOUT LOAD PROCESS
  if (item 1 goal = "lift-no-load") [
    ifelse (item 0 goal != 0) [
      set state? "lift-no-load"
      set goal replace-item 0 goal (item 0 goal - 1)
  ][
      set goal replace-item 0 goal t-liftl
      set goal replace-item 1 goal "lift-load"
    ]
  ]

;================================================== LIFT WITH LOAD PROCESS
  if (item 1 goal = "lift-load") [
    ifelse (item 0 goal != 0) [
      set state? "lift-load"
      set goal replace-item 0 goal (item 0 goal - 1)
  ][
      set gantry-position 1 ; set gantry position to where truck is (ycor 1)
      set goal replace-item 0 goal 0
      set goal replace-item 1 goal "deliver-container" ; deliver now!
    ]
  ]
;==================================================
  if (item 1 goal = "deliver-container") [
    if (item 2 goal = nobody) [ ;if another cranes just delivered this container
      set goal []
      set crane-idle crane-idle + 1
      set state? "idle"
      stop
    ]

; from pak medit
;    ifelse (item 0 goal != 0) [
;      set goal replace-item 0 goal (item 0 goal - 1)
;      set crane-service crane-service + 1
;    ][
;      deliver-container (item 2 goal)
;      set crane-idle crane-idle + 1
;    ]
; original code
    deliver-container (item 2 goal)
  ]
end

;Returns a list of the patch coords the crane must follow to go from xstart,ystart to xend,yend
;Assumes that either xstart=xend or ystart=yend
;The return path omits xstart,ystart but includes xend,yend
to-report make-path [xstart ystart xend yend]
  if (xstart = xend) [
    let increment ifelse-value (ystart > yend) [1][-1]
    let result []
    let p yend
    repeat abs (ystart - yend) [
      set result fput (list xstart p) result
      set p p + increment
    ]
    report result
  ]
  if (ystart = yend) [
    let increment ifelse-value (xstart > xend) [1][-1]
    let result []
    let p xend
    repeat abs (xstart - xend) [
      set result fput (list p ystart) result
      set p p + increment
    ]
    report result
  ]
  ;both x & y coords are different
  ;disabled, it may not affect simulation (need to be checked)
;  show (word "ERROR: make-path:" xstart "," ystart "  " xend "," yend)
  report []
end

;reports the shortest path from our current xcor,ycor to goal-x,goal-y
;returns list [[x1 y1][x2 y2]....] where xi yi are the positions (patch coordinates) the crane must follow, in order.
to-report path-to-xy [goal-x goal-y]
   if (ycor = goal-y) [;I am in the same W<->E as the goal
    report make-path xcor ycor goal-x goal-y
  ]
  if (member? xcor crane-road-xcors) [ ; I am traveling N<->S
    report (sentence (make-path xcor ycor xcor goal-y) (make-path xcor goal-y goal-x goal-y))
  ]
  ;I am not in the same ycor as the goal, find shortest route
;  let all-distances map [(abs (xcor - ?)) + abs (goal-x - ?)] crane-road-xcors
  let all-distances map [i -> (abs (xcor - i)) + abs (goal-x - i)] crane-road-xcors
  let best-crossroad item (position (min all-distances) all-distances) crane-road-xcors
  let other-ycor first filter [i -> i != ycor] crane-road-ycors
; let other-ycor first filter [? != ycor] crane-road-ycors
  report (sentence (make-path xcor ycor best-crossroad ycor) (make-path best-crossroad ycor best-crossroad other-ycor) (make-path best-crossroad other-ycor goal-x goal-y))
end

to-report path-to-group-stack [group stack]
  let goal-pos position-in-yard group stack -1
  let goal-x first goal-pos
  let goal-y item 1 goal-pos
  report path-to-xy goal-x goal-y
end

to-report path-to-truck [the-truck]
  report path-to-xy [xcor] of the-truck [ycor + 7] of the-truck
end


;returns the length of the minimum path to goal-x,goal-y. This function is similar to path-to-xy but does not create the path, so its faster.
to-report distance-to-xy [goal-x goal-y]
  if (ycor = goal-y) [;I am in the same W<->E as the goal
    report abs (xcor - goal-x)
  ]
  if (member? xcor crane-road-xcors) [ ; I am traveling N<->S
    report abs (ycor - goal-y) + abs (xcor - goal-x)
  ]
  ;I am not in the same ycor as the goal, find shortest route
  let all-distances map [i -> (abs (xcor - i)) + abs (goal-x - i)] crane-road-xcors
  let best-crossroad item (position (min all-distances) all-distances) crane-road-xcors
  let other-ycor first filter [i -> i != ycor] crane-road-ycors
  report abs (xcor - best-crossroad) + abs (ycor - other-ycor) + abs (best-crossroad - goal-x)
end

to-report distance-to-group-stack [group stack]
  let goal-pos position-in-yard group stack -1
  report distance-to-xy (first goal-pos) (item 1 goal-pos)
end

to-report distance-to-truck [the-truck]
  report distance-to-xy [xcor] of the-truck [ycor + 7] of the-truck
end

;Moves at most one step towards group,stack using the shortest route.
;But, if there is a crane in the position that I want to go then I say put
to goto-position [group stack]
  let path path-to-group-stack group stack
  if (length path = 0) [stop]
  let next first path
  set heading towardsxy (first next) (item 1 next)
  if (not any? cranes-on patch-ahead 1) [
    forward 1
  ]
end

;reports true if the crane does not need to change its heading to follow path
to-report path-in-heading? [path]
  if (length path = 0) [ ;if path is empty then we don't need to change heading
    report true
  ]
  let pos first path
  report (heading = towardsxy (first pos) (item 1 pos))
end

;Decide which truck to service
;returns the [group stack] of a random truck
to-report pick-goal-position
  let chosen-truck one-of trucks with [not waiting]
  if (chosen-truck = nobody) [
    report nobody]
;  ask chosen-truck [set color yellow]
  report [group-stack] of chosen-truck
end

;returns the [group stack] of the truck that has waited the longest
to-report pick-goal-position-fcfo
  let chosen-truck min-one-of (trucks with [not waiting and member? ycor list 0 0] ) [my-start-time]
  if (chosen-truck = nobody) [
    report nobody
  ]
  ask chosen-truck [
    set service-time ticks
    set on-service true
;    set color yellow
  ]
;  ask chosen-truck [set color yellow]
  report [group-stack] of chosen-truck
end

;Pick the truck that maximizes utility-eq-1
to-report pick-goal-position-distance
  let chosen-truck max-one-of (trucks with [not waiting]) [utility-eq-1 myself]
  if (chosen-truck = nobody) [
    report nobody
  ]
  ask chosen-truck [
    set service-time ticks
    set on-service true
;    set color yellow
  ]
   report [group-stack] of chosen-truck
end

to-report trucks-in-this-stack
  report trucks with [xcor = [xcor] of myself and ycor = ([ycor] of myself - 7)]
end

;moves the-container to the truck it belongs to, if the-container has no other containers on top of itself
;if the-container has another container on top then the top container is moved to the lowest pile in the stack
to deliver-container [the-container]
  let pile-height max ([z-cor] of containers-on the-container)

  ifelse ([z-cor] of the-container = pile-height) [ ;the-container is at the top
    let the-truck trucks-in-this-stack
    let the-containers-in-stack []
    let actual-wait-time 0

    set num-trucks-serviced num-trucks-serviced + 1
    set num-trucks-serviced-session num-trucks-serviced-session + 1
    ask the-truck [
      set actual-wait-time ticks - my-start-time
      set the-containers-in-stack containers-in-stack
      set total-wait-time total-wait-time + (ticks - my-start-time)
      set idle-time idle-time - current-idle ; update the idling time by reducing value of serviced trucks
      set total-service-time total-service-time + (ticks - service-time) ; update service time
      set total-terminal-time total-terminal-time + (ticks - my-terminal-time) ; update terminal time
      set total-queue-time total-queue-time + my-queue-time ; update queue time

      ; count wait times separately
      ifelse book? = true [
        set total-appointment-wt total-appointment-wt + (ticks - my-start-time)
        set total-appointment-st total-appointment-st + (ticks - service-time)
        set total-appointment-qt total-appointment-qt + (service-time - my-start-time)
      ][
        set total-walkin-wt total-walkin-wt + (ticks - my-start-time)
        set total-walkin-st total-walkin-st + (ticks - service-time)
        set total-walkin-qt total-walkin-qt + (service-time - my-start-time)
      ]

      ask my-client [
        if book? = false [die] ; if it a walk ins then do not count for app time

        set my-wait-time actual-wait-time
        estimate-cost my-type ; trigger cost estimation

        set total-app-time total-app-time + (ticks - my-start-time)
        set num-app-serviced num-app-serviced + 1

        if my-type = 1 [set tc-1-serviced tc-1-serviced + 1]
        if my-type = 2 [set tc-2-serviced tc-2-serviced + 1]
        if my-type = 3 [set tc-3-serviced tc-3-serviced + 1]

        die]
      die]

    set goal []
    ask the-container [die]

;;;; truck waiting rules
    let containers-with-truck the-containers-in-stack with [my-truck != nobody]
    if (any? containers-with-truck) [
      ask (one-of [my-truck] of containers-with-truck) [ ;if any trucks are waiting for this spot, pick one and move him here
        goto-container
        set waiting false ; mark that their stack is empty so they can get called in next do-move action
      ]
    ]
;;;;;
    stop
  ][ ;the-container is not at the top, move top container to smallest column in this stack

    set total-reshuffle total-reshuffle + 1 ; record the reshuffling activities done
    set total-reshuffle-time total-reshuffle-time + ticks-to-rehandle ; record total time to reshuffle
;    set state? "reshuffle"

    let the-container-column ([ycor] of the-container - ycor) ; the value is 0
    let other-columns remove the-container-column (list -1 -2 -3 -4 -5 -6)
    let min-column-height min (map [ i -> count containers-at 0 i] other-columns)
;    let min-column-height min (map [count containers-at 0 ?]) other-columns
;    let min-columns filter [count containers-at 0 ? = min-column-height] other-columns
    let min-columns filter [ i -> count containers-at 0 i = min-column-height] other-columns
    let destination one-of min-columns
    ;move the top container to destination
    ask max-one-of (containers-at 0 the-container-column) [z-cor] [
      move-to-position ([ycor] of myself + destination)
    ]
;to make the moving of each container take 3 steps uncomment the following line
; if commented, the container reshuffling will be instaneous
;    set goal (list ticks-to-rehandle "deliver-container" the-container)
  ]
end

;utility functions: these are truck functions. Each one takes the-crane as argument and returns the utility to the crane for delivering a container to this truck

;utility eq-1: distance-based utility.  The further a truck, the lower its utility.
;utility = 0 - distance(the-crane) - 1000 (if some other crane is on the path to the-crane) - 1000 (if a turn is required)
;  "turn is required" means that the current heading of the crane is NOT the same heading required for the first move in path-to-the-crane
to-report utility-eq-1 [the-crane]
  let path-to-the-crane path-to-crane the-crane
  let other-cranes-coords [(list xcor ycor)] of (cranes with [self != the-crane])
  let other-cranes-in-path-process (map [i -> member? i path-to-the-crane] other-cranes-coords)
;  let other-crane-in-path? reduce [ [a b] -> a or b] other-cranes-in-path-process
  ;  let other-crane-in-path? reduce [?1 or ?2] (map [member? ? path-to-the-crane] other-cranes-coords)
  let turn-required? false
  if ([ycor] of the-crane != [ycor + 7] of self) [set turn-required? true]
  let keep-heading? [path-in-heading? path-to-the-crane] of the-crane
;  report 0 - distance-to-crane the-crane - ifelse-value (other-crane-in-path?)[10000][0] - ifelse-value (turn-required?)[1000][0] - ifelse-value (keep-heading?)[0][1000] ; for multi crane problem
  report 0 - distance-to-crane the-crane - ifelse-value (turn-required?)[1000][0] - ifelse-value (keep-heading?)[0][1000]
end

;container moves to ypos, resets his z-cor to be at the top of the new column
to move-to-position [ypos]
  set my-row my-row + (ycor - ypos)
  set ycor ypos
  ifelse (any? other containers-here) [
    set z-cor 1 + max [z-cor] of other containers-here
  ][
    set z-cor 0
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
7
14
561
257
-1
-1
13.0
1
10
1
1
1
0
1
1
1
0
41
0
17
0
0
1
ticks
30.0

BUTTON
572
15
696
48
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
1569
130
1741
163
walk-ins
walk-ins
0
1
0.0
0.01
1
NIL
HORIZONTAL

SLIDER
1568
166
1740
199
no-shows
no-shows
0
1
0.0
0.01
1
NIL
HORIZONTAL

SWITCH
573
187
697
220
opportunistic?
opportunistic?
0
1
-1000

CHOOSER
572
140
697
185
crane-pick-goal-function
crane-pick-goal-function
"FCFS" "distance"
0

BUTTON
573
51
696
84
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
1569
59
1741
92
slot-per-session
slot-per-session
1
40
1.0
1
1
NIL
HORIZONTAL

PLOT
815
1385
1015
1535
appointment lead time
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot avg-app-time"

PLOT
3
1234
203
1384
average wait time
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot avg-wait-time"
"app" 1.0 0 -8732573 true "" "plot avg-appointment-wt"
"walk-in" 1.0 0 -2674135 true "" "plot avg-walkin-wt"

PLOT
7
1072
207
1222
Crane Utilization
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot crane-utilization"

MONITOR
1567
10
1623
55
NIL
sessions
17
1
11

PLOT
613
1385
813
1535
clients
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot count clients"
"walk-in" 1.0 0 -2674135 true "" "plot count clients with [book? = false]"
"app" 1.0 0 -10899396 true "" "plot count clients with [book? = true]"

PLOT
610
1235
810
1385
waiting trucks
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count trucks with [waiting = true]"

SLIDER
1569
94
1741
127
interval
interval
0
300
60.0
1
1
sec
HORIZONTAL

PLOT
1215
266
1415
416
Trucks Serviced
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot num-trucks-serviced"

CHOOSER
572
92
697
137
sequencing
sequencing
"loose-appointment" "strict-appointment" "random" "free"
3

PLOT
5
1385
205
1535
no shows / appointment
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -7500403 true "" "plot actual-no-show-rate"

MONITOR
2
1743
312
1788
NIL
count trucks with [member? ycor list 7 7 and cargo = nobody]
17
1
11

MONITOR
3
1791
312
1836
NIL
count clients with [book? = true and cargo = nobody]
17
1
11

PLOT
410
1072
610
1222
Spillover
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot spillover"
"walk-in" 1.0 2 -2674135 true "" "plot spillover-walkin"
"app" 1.0 2 -10899396 true "" "plot spillover-app"

MONITOR
1
1689
547
1734
NIL
stack-list
17
1
11

MONITOR
1624
10
1731
55
appointment clients
count clients with [book? = true]
17
1
11

MONITOR
1731
10
1820
55
walk-in clients
count clients with [book? = false]
17
1
11

PLOT
412
267
612
417
Avg. Service Time
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot avg-both-st"
"walk-in" 1.0 0 -2674135 true "" "plot avg-walkin-st"
"app" 1.0 0 -10899396 true "" "plot avg-appointment-st"

PLOT
210
267
410
417
Avg. Wait Time
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot avg-both-qt"
"walk-in" 1.0 0 -2674135 true "" "plot avg-walkin-qt"
"app" 1.0 0 -10899396 true "" "plot avg-appointment-qt"

PLOT
9
267
209
417
Avg. Truck Turn Time
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot avg-both-ta"
"queue" 1.0 0 -2674135 true "" "plot avg-both-qt"
"service" 1.0 0 -10899396 true "" "plot avg-both-st"

PLOT
206
1233
406
1383
TTA - appointment
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot avg-appointment-wt"
"queue" 1.0 0 -2674135 true "" "plot avg-appointment-qt"
"service" 1.0 0 -10899396 true "" "plot avg-appointment-st"

PLOT
408
1233
608
1383
TTA - walk-in
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot avg-walkin-wt"
"queue" 1.0 0 -2674135 true "" "plot avg-walkin-qt"
"service" 1.0 0 -10899396 true "" "plot avg-walkin-st"

PLOT
209
1536
408
1686
crane co2 activity
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot crane-emission-activity-co2"

PLOT
2
1536
206
1686
trucks co2 activity
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot truck-emission-activity-co2"

SWITCH
1585
495
1756
528
overbook?
overbook?
1
1
-1000

PLOT
207
1383
407
1533
overbooking
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"slots" 1.0 0 -7500403 true "" "plot slot-per-session"
"overbook" 1.0 0 -2674135 true "" "plot total-actual-bookings"

PLOT
209
1072
409
1222
Queue Length
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot queue-length"

PLOT
7
920
207
1070
Total CO2
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot both-co2"
"truck" 1.0 0 -2674135 true "" "plot total-truck-co2"
"crane" 1.0 0 -10899396 true "" "plot total-crane-co2"

PLOT
208
920
408
1070
Total CO
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot both-co"
"truck" 1.0 0 -2674135 true "" "plot total-truck-co"
"crane" 1.0 0 -10899396 true "" "plot total-crane-co"

PLOT
410
919
610
1069
Total NOx
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot both-nox"
"truck" 1.0 0 -2674135 true "" "plot total-truck-nox"
"crane" 1.0 0 -10899396 true "" "plot total-crane-nox"

PLOT
612
919
812
1069
Total PM
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot both-pm"
"truck" 1.0 0 -2674135 true "" "plot total-truck-pm"
"crane" 1.0 0 -10899396 true "" "plot total-crane-pm"

PLOT
814
919
1014
1069
Total THC
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total" 1.0 0 -7500403 true "" "plot both-thc"
"truck" 1.0 0 -2674135 true "" "plot total-truck-thc"
"crane" 1.0 0 -10899396 true "" "plot total-crane-thc"

MONITOR
1588
278
1713
323
NIL
num-trucks-serviced
17
1
11

MONITOR
1371
11
1561
56
NIL
count clients with [my-type = 1]
17
1
11

MONITOR
1372
60
1562
105
NIL
count clients with [my-type = 2]
17
1
11

MONITOR
1371
110
1561
155
NIL
count clients with [my-type = 3]
17
1
11

SWITCH
704
15
824
48
ignore-slot?
ignore-slot?
0
1
-1000

SLIDER
703
52
823
85
n-for-each-tc
n-for-each-tc
0
30
6.0
1
1
NIL
HORIZONTAL

SLIDER
953
16
1104
49
trucks-ewt
trucks-ewt
1
3000
1.0
1
1
NIL
HORIZONTAL

SLIDER
953
52
1104
85
trucks-ewt-variance
trucks-ewt-variance
0
0.5
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
826
52
949
85
tc-1-bound
tc-1-bound
0
3600
600.0
1
1
NIL
HORIZONTAL

SLIDER
826
87
949
120
tc-2-bound
tc-2-bound
0
3600
1200.0
1
1
NIL
HORIZONTAL

SLIDER
826
123
950
156
tc-3-bound
tc-3-bound
0
3600
1800.0
1
1
NIL
HORIZONTAL

SWITCH
826
16
950
49
negotiation?
negotiation?
1
1
-1000

SLIDER
952
88
1104
121
alpha
alpha
1
10
1.0
1
1
NIL
HORIZONTAL

SLIDER
953
123
1104
156
beta
beta
1
10
1.0
1
1
NIL
HORIZONTAL

PLOT
812
266
1012
416
Avg. Estimated Cost
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"tc-1" 1.0 0 -10899396 true "" "plot avg-est-cost-1"
"tc-2" 1.0 0 -13345367 true "" "plot avg-est-cost-2"
"tc-3" 1.0 0 -2674135 true "" "plot avg-est-cost-3"
"all" 1.0 0 -7500403 true "" "plot avg-est-cost-all"

PLOT
1013
266
1214
417
Prediction
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"est" 1.0 0 -2674135 true "" "plot current-estimation"
"act" 1.0 0 -7500403 true "" "plot avg-both-ta"

PLOT
611
267
811
417
Avg. Inconvenience Cost
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"all" 1.0 0 -7500403 true "" "plot avg-inc-cost-all"
"tc-1" 1.0 0 -10899396 true "" "plot avg-inc-cost-1"
"tc-2" 1.0 0 -13345367 true "" "plot avg-inc-cost-2"
"tc-3" 1.0 0 -2674135 true "" "plot avg-inc-cost-3"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="negotiation-pilot-1" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>avg-both-ta</metric>
    <metric>avg-both-st</metric>
    <metric>avg-both-qt</metric>
    <metric>num-trucks-serviced</metric>
    <enumeratedValueSet variable="sequencing">
      <value value="&quot;free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="negotiation?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alpha">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-2-bound">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="beta">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-shows">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interval">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opportunistic?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-for-each-tc">
      <value value="5"/>
      <value value="7"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt">
      <value value="600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ignore-slot?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt-variance">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slot-per-session">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="walk-ins">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-3-bound">
      <value value="3600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-1-bound">
      <value value="1200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overbook?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crane-pick-goal-function">
      <value value="&quot;FCFS&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="negotiation-1-9" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>avg-both-ta</metric>
    <metric>avg-both-st</metric>
    <metric>avg-both-qt</metric>
    <metric>num-trucks-serviced</metric>
    <metric>avg-est-cost-1</metric>
    <metric>avg-est-cost-2</metric>
    <metric>avg-est-cost-3</metric>
    <enumeratedValueSet variable="sequencing">
      <value value="&quot;free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="negotiation?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alpha">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-2-bound">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="beta">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-shows">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interval">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opportunistic?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-for-each-tc">
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt">
      <value value="2716"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ignore-slot?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt-variance">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slot-per-session">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="walk-ins">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-3-bound">
      <value value="3600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-1-bound">
      <value value="1200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overbook?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crane-pick-goal-function">
      <value value="&quot;FCFS&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="negotiation-1-7" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>avg-both-ta</metric>
    <metric>avg-both-st</metric>
    <metric>avg-both-qt</metric>
    <metric>num-trucks-serviced</metric>
    <metric>avg-est-cost-1</metric>
    <metric>avg-est-cost-2</metric>
    <metric>avg-est-cost-3</metric>
    <enumeratedValueSet variable="sequencing">
      <value value="&quot;free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="negotiation?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alpha">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-2-bound">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="beta">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-shows">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interval">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opportunistic?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-for-each-tc">
      <value value="7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt">
      <value value="524"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ignore-slot?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt-variance">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slot-per-session">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="walk-ins">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-3-bound">
      <value value="3600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-1-bound">
      <value value="1200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overbook?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crane-pick-goal-function">
      <value value="&quot;FCFS&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="negotiation-1-5" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>avg-both-ta</metric>
    <metric>avg-both-st</metric>
    <metric>avg-both-qt</metric>
    <metric>num-trucks-serviced</metric>
    <metric>avg-est-cost-1</metric>
    <metric>avg-est-cost-2</metric>
    <metric>avg-est-cost-3</metric>
    <enumeratedValueSet variable="sequencing">
      <value value="&quot;free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="negotiation?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alpha">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-2-bound">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="beta">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-shows">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interval">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opportunistic?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-for-each-tc">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt">
      <value value="288"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ignore-slot?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt-variance">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slot-per-session">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="walk-ins">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-3-bound">
      <value value="3600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-1-bound">
      <value value="1200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overbook?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crane-pick-goal-function">
      <value value="&quot;FCFS&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="negotiation-2" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>avg-both-ta</metric>
    <metric>avg-both-st</metric>
    <metric>avg-both-qt</metric>
    <metric>num-trucks-serviced</metric>
    <metric>avg-est-cost-1</metric>
    <metric>avg-est-cost-2</metric>
    <metric>avg-est-cost-3</metric>
    <metric>avg-est-cost-all</metric>
    <enumeratedValueSet variable="sequencing">
      <value value="&quot;free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="negotiation?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alpha">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-2-bound">
      <value value="1200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="beta">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-shows">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interval">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opportunistic?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-for-each-tc">
      <value value="5"/>
      <value value="7"/>
      <value value="8"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ignore-slot?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt-variance">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slot-per-session">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="walk-ins">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-3-bound">
      <value value="1800"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-1-bound">
      <value value="600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overbook?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crane-pick-goal-function">
      <value value="&quot;FCFS&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="negotiation-3" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>avg-both-ta</metric>
    <metric>avg-both-st</metric>
    <metric>avg-both-qt</metric>
    <metric>num-trucks-serviced</metric>
    <metric>avg-est-cost-1</metric>
    <metric>avg-est-cost-2</metric>
    <metric>avg-est-cost-3</metric>
    <metric>avg-est-cost-all</metric>
    <metric>avg-inc-cost-1</metric>
    <metric>avg-inc-cost-2</metric>
    <metric>avg-inc-cost-3</metric>
    <metric>avg-inc-cost-all</metric>
    <enumeratedValueSet variable="sequencing">
      <value value="&quot;free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="negotiation?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alpha">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-2-bound">
      <value value="1200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="beta">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-shows">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interval">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="opportunistic?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-for-each-tc">
      <value value="6"/>
      <value value="7"/>
      <value value="8"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ignore-slot?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trucks-ewt-variance">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slot-per-session">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="walk-ins">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-3-bound">
      <value value="1800"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tc-1-bound">
      <value value="600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overbook?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crane-pick-goal-function">
      <value value="&quot;FCFS&quot;"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
