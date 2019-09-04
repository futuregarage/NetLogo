breed [trucks truck]
breed [containers container]
breed [cranes crane]
breed [clients client]

clients-own [
  my-truck
  cargo
  my-start-time
  book?
  order
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
  num-no-shows
  current-interval
  total-appointment-wt
  total-walkin-wt
  globals-order
  spillover
  spillover-app
  spillover-walkin
  stack-list
]

to setup
  clear-all
  reset-ticks
  init-globals
  init-world
  init-crane
  init-container
  init-client
end

to go
  ; check session
  let list-session (list 0 3600 7200 10800 14400 18000 21600 25200 28800 32400)
  if ticks >= 36000 [ ; stop after 10 hour
    count-spillover ; count for the last session (tick 36000)
    stop
  ]

  if (member? ticks list-session) [
    set sessions sessions + 1
    count-spillover
    if run? = true [
      init-container
      init-client
      do-appointment
    ]
  ]

  do-walk-in
  do-arrive
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
  if ntruck >= slot-per-session [stop] ; set the threshold for trucks allowed inside based on slot per sessions

  ; choose the truck to be let inside
  let booked-truck count trucks with [member? ycor wlane and book? = true]
  let the-truck 0

  ; sequence 1
  if sequencing = "random" [ ; randomly let any trucks
    set the-truck one-of trucks with [waiting = false and my-crane = nobody]
  ]

  ; sequence 2
  if sequencing = "appointment-first" [ ; let the one with appointment first, then the walk ins for the remaining slots
    ifelse booked-truck > 0 [
      set the-truck one-of trucks with [waiting = false and my-crane = nobody and book? = true]
    ][
;      ifelse current-interval = interval [ ; use interval delay, adjusted in do-arrive procedure
      set the-truck one-of trucks with [waiting = false and my-crane = nobody]
;      ]
;      [stop]
    ]
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
  set ticks-to-rehandle 40 ; number of ticks it takes for crane to move container from one place to another in the same stack.
  set ticks-to-deliver 50 ;number of ticks it takes for crane to move container from stack to truck
  set ticks-to-move 6 ;number of ticks it takes for the crane to move to an adjacent container
  set decommitment-penalty 1000
  set crane-road-xcors (list 0 8 9 10 11 12)
  set crane-road-ycors (list 0 41)
end

to init-world
  ask patches with [pycor = 0 or pycor = 7] [ set pcolor gray ]
  ask patches with [pycor > 0 and pycor < 7] [set pcolor white]
  ask patches with [pycor > 7 and pycor < 13] [set pcolor 6.7]
  ask patches with [pycor > 12] [set pcolor 7.7]
end

to init-container
  let amt 500
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
  ]
end

to init-client
  let n-client count clients
  let buffer max list 0 (n-demand - n-client)
  create-clients buffer [
    let my-x random max-pxcor
    let my-y (random 5) + 13
    setxy my-x my-y
    set shape "person"
    set color black
    set cargo nobody
    set my-truck nobody
    set book? 0 ; as an indicator of a new client
  ]
end

to do-appointment ; appointments are made in each beginning of sessions
  set stack-list [] ; a list of stack that has been booked, reset every new session
  repeat slot-per-session [
    let the-client one-of clients with [book? = 0]
    if (the-client = nobody) [stop]

    ;function to choose only cargo that is not on stack-list
    let the-cargo one-of containers with [my-truck = nobody and pick-me = false and not member? my-stack stack-list]

    if (the-cargo = nobody) [stop]
    ask the-client [
      set book? true
      set my-start-time ticks
      set color green
      set cargo the-cargo
      if (cargo = nobody) [die stop] ; all stacks are full!!
      ask cargo [
        ; set color appointment
        set color green
        set size 1
        ]
      set my-truck nobody

      ;update the stack-list
      set stack-list fput [my-stack] of cargo stack-list
    ]
  ]
end

to do-walk-in ; walk ins are generated each interval (second)
  ifelse current-interval = interval [
    let the-client one-of clients with [cargo = nobody]
    if (the-client = nobody) [stop]
    let the-cargo one-of containers with [my-truck = nobody and pick-me = false]
    if random-float 1.0 < walk-ins [
      ask the-client [
;        if (cargo = nobody) [die stop] ; all stacks are full!!
        set book? false
        set my-start-time ticks
        set color yellow
        set cargo the-cargo
        ask cargo [
          ; set color walk in
          set color yellow
          set size 1]
        set my-truck nobody
      ]
    ]
    set current-interval 0
  ][
  set current-interval current-interval + 1
  ]
end

to do-arrive ;ask a client to create his/her truck, with a prob of no show
  let the-client one-of clients with [cargo != nobody and my-truck = nobody]
  ifelse (the-client = nobody) [stop]
  [
  ifelse random-float 1.0 < no-shows [
    ask the-client [
      if book? = true [ ; does not count walk in no shows
        set num-no-shows num-no-shows + 1
      ]
      ask cargo [
        set color black
        set size .6
        set my-truck nobody
      ]
      die
    ]
  ][
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
;        if cargo = nobody [die stop]
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
  ]
  ]
end

to appointment-error-check
  let x count clients with [book? = true and cargo = nobody]
  if x > 0 [
    ask clients with [book? = true and cargo = nobody] [
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
;;;;;;;;;;;; REPORTERS

to-report crane-utilization
  if ticks = 0 [report 0]
  let the-crane one-of cranes
  let cidle [crane-idle] of the-crane
  report cidle / ticks
end

to-report avg-wait-time
  if num-trucks-serviced = 0 [report 0]
  report total-wait-time / num-trucks-serviced
end

to-report avg-app-time
  if num-app-serviced = 0 [report 0]
  report total-app-time / num-app-serviced
end

to-report actual-no-show-rate
  let x sessions + 1
  if x < 1 [report 0]
  report num-no-shows / (x * slot-per-session)
end

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

to-report avg-both-wt
  let x num-trucks-serviced
  if x = 0 [report 0]
  report (total-walkin-wt + total-appointment-wt) / x
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
      ;set color red ; color red to indicate its stack is occupied
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

    set crane-idle crane-idle + 1
    stop  ]
  if (empty? goal or (opportunistic? and item 1 goal = "goal-position")) [;no goal position or opportunistic, set new goal
    ifelse (any? trucks with [not waiting])[
      let goalp []

      ;;;;;; =============== crane choice of utility function starts =================
      if (crane-pick-goal-function = "FIFO") [set goalp pick-goal-position-fcfo]
      if (crane-pick-goal-function = "distance") [set goalp pick-goal-position-distance]
      ;;;;;;; ================= crane choice of utility function ends =======================

      ifelse (goalp != nobody) [ ; if a valid group and stack values are returned
        set goal (sentence ticks-to-move "goal-position" item 0 goalp item 1 goalp)
      ][
        set goal [] ; reset goal
        stop ; crane stay put until next tick

        set crane-idle crane-idle + 1
      ]
    ][
      stop
    ]
  ]

  if (item 1 goal = "goal-position") [ ;move towards goal-position
    let goal-position-xy position-in-yard (item 2 goal) (item 3 goal) -1
    goto-position (item 2 goal) (item 3 goal)

    set travel-distance travel-distance + 1 ; travel distance of the crane + 1

    if (not any? trucks-on (patch (item 0 goal-position-xy) (item 1 goal-position-xy - 7))) [ ;if there is no truck at the goal then reset goal
        set goal []
        stop
    ]
    if (item 0 goal-position-xy = xcor and item 1 goal-position-xy = ycor) [;we are at the goal, next time deliver container
      let the-truck trucks-in-this-stack

    ;;;;;;
    ask the-truck [
    set on-service true
    set service-time ticks] ; set on-service on truck true
    ;;;;;
      set goal (list ticks-to-deliver "deliver-container" (item 0 [cargo] of the-truck))
    ]
    stop
  ]
  if (item 1 goal = "deliver-container") [
    if (item 2 goal = nobody) [ ;if another cranes just delivered this container
      set goal []
      stop
    ]
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
  let chosen-truck min-one-of (trucks with [not waiting]) [my-start-time]
  if (chosen-truck = nobody) [
    report nobody]
;  ask chosen-truck [set color yellow]
  report [group-stack] of chosen-truck
end

;Pick the truck that maximizes utility-eq-1
to-report pick-goal-position-distance
  let chosen-truck max-one-of (trucks with [not waiting]) [utility-eq-1 myself]
  if (chosen-truck = nobody) [
    report nobody]
; original code
;   ask chosen-truck [set color yellow]
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

    set num-trucks-serviced num-trucks-serviced + 1
    ask the-truck [
      set the-containers-in-stack containers-in-stack
      set total-wait-time total-wait-time + (ticks - my-start-time)
      set idle-time idle-time - current-idle ; update the idling time by reducing value of serviced trucks
      set total-service-time total-service-time + (ticks - service-time) ; update service time
      set total-terminal-time total-terminal-time + (ticks - my-terminal-time) ; update terminal time
      set total-queue-time total-queue-time + my-queue-time ; update queue time

      ; count wait times separately
      ifelse book? = true [
        set total-appointment-wt total-appointment-wt + (ticks - my-start-time)
      ][
        set total-walkin-wt total-walkin-wt + (ticks - my-start-time)
      ]

      ask my-client [
        if book? = false [die] ; if it a walk ins then do not count for app time
        set total-app-time total-app-time + (ticks - my-start-time)
        set num-app-serviced num-app-serviced + 1
        die]
      die]

    set goal []
    ask the-container [die]
    let containers-with-truck the-containers-in-stack with [my-truck != nobody]

;;;; truck waiting rules
    if (any? containers-with-truck) [
      ask (one-of [my-truck] of containers-with-truck) [ ;if any trucks are waiting for this spot, pick one and move him here
;        goto-container
        set waiting false ; mark that their stack is empty so they can get called in next do-move action
      ]
    ]
;;;;;
    stop
  ][ ;the-container is not at the top, move top container to smallest column in this stack

    set total-reshuffle total-reshuffle + 1 ; record the reshuffling activities done
    set total-reshuffle-time total-reshuffle-time + ticks-to-rehandle ; record total time to reshuffle

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
    set goal (list ticks-to-rehandle "deliver-container" the-container)


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
9
271
72
304
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
578
16
750
49
n-demand
n-demand
0
100
40.0
1
1
NIL
HORIZONTAL

SLIDER
579
138
751
171
walk-ins
walk-ins
0
1
0.5
0.01
1
NIL
HORIZONTAL

SLIDER
578
179
750
212
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
766
128
921
161
opportunistic?
opportunistic?
0
1
-1000

CHOOSER
764
73
922
118
crane-pick-goal-function
crane-pick-goal-function
"FIFO" "distance"
1

BUTTON
80
272
143
305
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
578
57
750
90
slot-per-session
slot-per-session
0
40
20.0
1
1
NIL
HORIZONTAL

PLOT
210
334
410
484
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
415
333
615
483
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
6
333
206
483
crane utilization
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

SWITCH
163
274
253
307
run?
run?
0
1
-1000

MONITOR
274
270
330
315
NIL
sessions
17
1
11

PLOT
617
485
817
635
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
"total" 1.0 1 -7500403 true "" "plot count clients"
"walk-in" 1.0 0 -2674135 true "" "plot count clients with [book? = false]"
"app" 1.0 0 -10899396 true "" "plot count clients with [book? = true]"

PLOT
210
486
410
636
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
579
99
751
132
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
415
486
615
636
trucks serviced
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
764
16
921
61
sequencing
sequencing
"appointment-first" "random"
1

PLOT
5
487
205
637
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
"default" 1.0 1 -7500403 true "" "plot actual-no-show-rate"

MONITOR
6
711
316
756
NIL
count trucks with [member? ycor list 7 7 and cargo = nobody]
17
1
11

MONITOR
7
759
316
804
NIL
count clients with [book? = true and cargo = nobody]
17
1
11

PLOT
617
332
817
482
spillover
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
"total" 1.0 1 -7500403 true "" "plot spillover"
"walk-in" 1.0 2 -2674135 true "" "plot spillover-walkin"
"app" 1.0 2 -10899396 true "" "plot spillover-app"

MONITOR
5
657
551
702
NIL
stack-list
17
1
11

MONITOR
338
271
445
316
appointment clients
count clients with [book? = true]
17
1
11

MONITOR
452
272
541
317
walk-in clients
count clients with [book? = false]
17
1
11

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
