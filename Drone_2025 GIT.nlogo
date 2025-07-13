extensions [csv py queue]

globals [
  attendance                 ;; current values of drones working
  working                    ;; drones working (not recharging)
  history                    ;; list of past values of attendance
  home-patches               ;; agentset of green patches
  bar-patches                ;; agentset of blue patches
  _die                       ;; quantidade de drones mortos
  overcrowding-threshold1    ;; limiar mutavel pela quantidade de agentes
  serie_working              ;; valores hitoricos dos drones trabalhando
  time                       ;; valor de tempo
  listover                   ;; valores do threadshold
  listover1                  ;; Lista invertida
  total                      ;; total de agentes na simulação

  totalpredictorcomplex      ;; total de preditores complexos

  feedbackcsv                ;; nome csv feedback (x)
  serietempcsv               ;; nome serie temporal csv (y)

  batt ;; para o relatorio
]

breed [complexes complex]

turtles-own [

    ;;;;;;;;;;;;;;;;;;;;;;;;;VARIAVEIS PREDITORES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  strategies      ;; list of strategies
  best-strategy   ;; index of the current best strategy
  prediction      ;; current prediction of the bar attendance
  attend?         ;; true if the agent currently plans to attend the bar
  reward          ;; Quantity of time of drones didn't
  reward1         ;; contador intermediario - recarga
  rewardefetivo   ;; contador intermediario - recarga efetiva
  reward2         ;; contador intermediario - efetivo
  _battery        ;; Include battery profile (10/11/2020)
  _drone_usage    ;; perfil do uso dos drones
  is_full         ;; se SOC > p2_up
  can_recharging  ;; se p2lw<SOC<p2up
  need_recharging ;; se SOC<p2lw

]

to setup

  clear-all
  set-default-shape turtles "airplane"

  file-close-all ; fechar qualquer arquivo aberto da ultila vez

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;SETUP PYTHON ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    py:setup py:python
  (py:run
;    "import pandas as pd"
;    "import numpy as np"
    "import os"
    "import time"
    "import random"
  )
  ;; create the 'working place'
  set home-patches patches with
    [
      (pycor != ((pxcor > -5 and pxcor < 5) and pxcor != (pycor > -5 and pycor < 5)))
    ]
  ask home-patches
    [
      set pcolor green
    ]

  ;; create the 'bar 1'
  set bar-patches patches with
    [
      (pxcor > -5 and pxcor < 5) and (pycor > -5 and pycor < 5)
    ]
  ask bar-patches
    [
      set pcolor blue
    ]

  set overcrowding-threshold1 (overcrowding-threshold / 100 * drones)

;; create the agents and give them random strategies
  create-turtles drones
    [

      set color white
      move-to-empty-one-of home-patches

      ;; initialize the previous attendance randomly so the agents have a history
      ;; to work with from the start
      set history n-values (memory-size * 2) [random drones]
      ;; the history is twice the memory, because we need at least a memory worth of history
      ;; for each point in memory to test how well the strategies would have worked

      set attendance first history

      if (Policy = 1) or (Policy = 2)
        [
          set strategies n-values number-strategies [random-strategy]
          set best-strategy first strategies
          update-strategies
        ]

      set reward 1
      set reward1 0 ;contador intermediario reward

      set rewardefetivo 1
      set reward2 0 ;contador intermediario rewardefetivo

      set _battery 100
      set _die 0
      set is_full true
      set can_recharging false ;; se p2lw<SOC<p2up
      set need_recharging false ;; se SOC<p2lw

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Police 1 doesn have the safe mode, in this case was a pure El Farol model.;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

      if Policy = 1
        [
            set P2_upperlimit 100
            set P2_lowerlimit 0
        ]

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Police 0 Simpliest model - Don't use this variables;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

      ;Inicio dos vetores auxiliares
      set serie_working []
      set time []
      set total []

  ]

  ;; start the clock
  reset-ticks
end



to go

  ;Set drone_usage:::::::::::::::::::::::::::::::::
  ask turtles
    [
      ;update drone usage
      set _drone_usage random-normal ( Battery_consumption ) Battery_Consumption_SD
      ;limit usage battery
      if _drone_usage < 0 [set _drone_usage 0]
      if _drone_usage > 100 [set _drone_usage 100]
      ;kill the drones
      if _battery < 0 [die]

    ]
  ;:::::::::::::::::::::::::::::::::::::::::::::::::::

  check_battety
  ; Decision process attend?

  battery_level

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; remove energy
  ask turtles
    [
      set _battery _battery - _drone_usage
    ]



  ;; depending on their decision the turtles go to the bar or stay at home
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ask turtles
      [
        ifelse attend?
          [ ;1 - if
            set reward1 reward1 + 1
            set reward (1 - (reward1 / ( ticks + 1 )))

            ifelse (attendance <= overcrowding-threshold1)
             [ ;2  -if
                  move-to-empty-one-of bar-patches
                  set _battery _battery + Battery_Gain
                  if _battery > 100
                    [
                      set _battery 100
                    ]
                  set reward2 reward2 + 1
                  set rewardefetivo ( 1 - (reward2 / ( ticks + 1 ) ) )
              ]  ;2 -if

              [ ;2 -else
                move-to-empty-one-of home-patches
              ] ;2 -else

          ] ;1 -if
          [ ;1 -else
            move-to-empty-one-of home-patches
          ] ;1-else
      ]



  set attendance count turtles-on bar-patches



  set history fput (attendance) but-last history

  set total lput (count turtles) total
   ; criar serie temporal attendance

  set working (count turtles - attendance)

  set serie_working lput working serie_working

  set time lput ticks time

  set overcrowding-threshold1  (overcrowding-threshold / 100 * count turtles)

  if not any? turtles
  [
    stop
  ]

  ;; advance the clock
  tick
end


to update-strategies
  let best-score memory-size * drones + 1
  foreach strategies
    [ the-strategy ->
      let score 0
      let week 1
      repeat memory-size
        [
          set prediction predict-attendance the-strategy sublist history week (week + memory-size)
          set score score + sqrt ((item (week - 1) history - prediction) * (item (week - 1) history - prediction))
          set week week + 1
        ]
      if (score <= best-score)
        [
          set best-score score
          set best-strategy the-strategy
        ]
    ]
end

to-report random-strategy
  report n-values (memory-size + 1) [1.0 - random-float 2.0]
end

to-report predict-attendance [strategy subhistory]
  report ( count turtles ) * first strategy + sum (map [ [weight week] -> weight * week ] butfirst strategy subhistory)
end

to check_battety
  ask turtles
        [
        ( ifelse
          _battery >  P2_upperlimit

        ;if
            [
              set is_full true
              set can_recharging false ;; se p2lw<SOC<p2up
              set need_recharging false ;; se SOC<p2lw

            ]
        ;if
           _battery < P2_lowerlimit
            [
              set is_full false
              set can_recharging false ;; se p2lw<SOC<p2up
              set need_recharging true ;; se SOC<p2lw

            ]
          [
        ;else - Logica ElFarol Bar

      if (Policy = 1) or (Policy = 2)
            [
              set is_full false
              set can_recharging true ;; se p2lw<SOC<p2up
              set need_recharging false ;; se SOC<p2lw

        ]
      ] )
    ]
end

to battery_level

      ask turtles
      [
        ( ifelse
          _battery >  P2_upperlimit

        ;if
            [
              set attend? false
              set color yellow
              ;print("Falso")
            ]
        ;if
           _battery < P2_lowerlimit
            [
              set attend? true
              set color red
              ;print("Socorro")

            ]
          [
        ;else - Logica ElFarol Bar

      if (Policy = 1) or (Policy = 2)
            [
              set prediction predict-attendance best-strategy sublist history 0 memory-size
              set attend? (prediction <= overcrowding-threshold1)
              set color white
              ;print(who)
              ;print(attend?)
              ;print(prediction)
              ;print(overcrowding-threshold1)
              ;print("---------")

        update-strategies
        ]
      ] )
    ]
end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;CRIACAO REPORTERES;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to createreport


    py:set "limiar" overcrowding-threshold
    py:set "temposim" ticks
    py:set "predictor" number-strategies
    py:set "BG" Battery_Gain
    py:set "RC" Battery_consumption
    py:set "Usage_randon" Battery_consumption_SD * 100
    py:set "Drones" drones
    py:set "police" policy
    py:set "memory" memory-size
    py:set "Up" p2_upperlimit
    py:set "Low" p2_lowerlimit



  (py:run
    "tick = str(time.time())"
    "x = ('resultstestes/Micro_'+ 'Pol_' + str(police) + '_Drones_' + str(Drones) + '_Cons_' + str(RC) + '_Rand_' + str(Usage_randon) + '_Low_' + str(Low) + '_Lim_' + str(limiar) + '_Gain_' + str(BG) + '_UP_' + str(Up) + '_Mem_' + str(memory) + '_Pred_' + str(predictor) + '_TempoSIM_' + str(temposim) + '_#_'+ tick  + '.csv')"
    "y = ('resultstestes/Macro_'+ 'Pol_' + str(police) + '_Drones_' + str(Drones) + '_Cons_' + str(RC) + '_Rand_' + str(Usage_randon) + '_Low_' + str(Low) + '_Lim_' + str(limiar) + '_Gain_' + str(BG) + '_UP_' + str(Up) + '_Mem_' + str(memory) + '_Pred_' + str(predictor) + '_TempoSIM_' + str(temposim) + '_#_'+ tick  + '.csv')"
   )

    set feedbackcsv py:runresult "x"
    set serietempcsv py:runresult "y"

  csv:to-file feedbackcsv [ (list who _battery reward rewardefetivo  ) ] of turtles
  csv:to-file serietempcsv (list time serie_working total )

end


to move-to-empty-one-of [locations]  ;; turtle procedure
  move-to one-of locations
end
@#$#@#$#@
GRAPHICS-WINDOW
535
35
1068
569
-1
-1
15.0
1
24
1
1
1
0
1
1
1
-17
17
-17
17
1
1
1
ticks
30.0

BUTTON
440
30
503
63
go
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
0

BUTTON
356
66
434
100
setup
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

SLIDER
80
35
270
68
memory-size
memory-size
1
15
9.0
1
1
NIL
HORIZONTAL

SLIDER
80
70
270
103
number-strategies
number-strategies
1
10
9.0
1
1
NIL
HORIZONTAL

SLIDER
80
105
270
138
overcrowding-threshold
overcrowding-threshold
0
100
50.0
10
1
NIL
HORIZONTAL

PLOT
1075
40
1280
260
Battery Distribution
NIL
NIL
0.0
100.0
0.0
10.0
true
false
"" "set-plot-y-range 0 1\n  set-plot-x-range 0 (max [ _battery ] of turtles + 1)"
PENS
"pen-0" 5.0 1 -16777216 true "" "histogram [ _battery ] of turtles"

SLIDER
315
245
510
278
Battery_Gain
Battery_Gain
0
100
100.0
10
1
NIL
HORIZONTAL

SLIDER
320
405
517
438
Battery_consumption
Battery_consumption
0
20
15.0
1
1
NIL
HORIZONTAL

BUTTON
355
30
435
63
Debug
go
NIL
1
T
OBSERVER
NIL
D
NIL
NIL
1

TEXTBOX
10
195
300
346
Battery swap  -> Battery_Gain = 100\n\nBattery Gain (BG): Quantity of energy recharged in charger visit\n
18
0.0
1

TEXTBOX
5
155
475
201
RECHARGE / BATTERY SWAPPING CONTROL
20
0.0
1

TEXTBOX
15
330
320
376
DRONE USAGE CONTROL
20
0.0
1

TEXTBOX
10
390
250
565
Control of the quantity of energy (BC) used in each cicle.\n\n- Can be select a randomic value by each cicle per each drone
18
0.0
1

SLIDER
320
650
515
683
Policy
Policy
0
2
0.0
1
1
NIL
HORIZONTAL

TEXTBOX
8
582
253
818
Polices:\n0 - Simplier model\n1 - Use PEFB to take the decision\n2 - \"Safe Mode\" that depends of the battery status %C to define
18
0.0
1

BUTTON
440
65
505
100
Report
createreport\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
10
41
70
86
m -->
18
0.0
1

TEXTBOX
10
75
65
96
k -->
18
0.0
1

TEXTBOX
10
115
65
136
B -->
18
0.0
1

TEXTBOX
10
10
295
28
SIMULATION PARAMETERS
20
0.0
1

TEXTBOX
545
15
850
61
DRONES WORKING AREA
20
0.0
1

TEXTBOX
1095
10
1375
56
SIMULATION OUTPUTS
20
0.0
1

TEXTBOX
5
559
235
605
POLICY DECISION
20
0.0
1

SLIDER
520
610
692
643
p2_upperlimit
p2_upperlimit
0
100
70.0
10
1
NIL
HORIZONTAL

SLIDER
520
650
692
683
p2_lowerlimit
p2_lowerlimit
0
100
20.0
10
1
NIL
HORIZONTAL

PLOT
1405
270
1645
455
_drone_usage
NIL
NIL
0.0
15.0
0.0
15.0
true
true
"" ""
PENS
"Max _usg" 1.0 0 -2139308 true "" "plot max [_drone_usage] of turtles"
"Usage" 1.0 0 -13345367 true "" "plot mean [_drone_usage] of turtles"
"Min _usg" 1.0 0 -11085214 true "" "plot min [_drone_usage] of turtles"

PLOT
1295
40
1505
260
Utility Histogram
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" "set-plot-y-range 0 1\n  set-plot-x-range 0 1"
PENS
"default" 0.01 1 -16777216 true "" "histogram [ reward ] of turtles"

TEXTBOX
920
590
1170
667
Classic\n
30
0.0
1

MONITOR
935
635
1015
680
Threshold
overcrowding-threshold1
3
1
11

TEXTBOX
582
594
626
612
Yellow
12
0.0
1

TEXTBOX
590
693
627
711
Red
12
0.0
1

TEXTBOX
1515
35
1665
116
Utility:\n1 - Working\n0 - Not Working (recharging place)
12
0.0
1

SLIDER
322
610
516
643
drones
drones
0
100
100.0
1
1
NIL
HORIZONTAL

MONITOR
714
700
769
745
Work
count turtles - attendance
17
1
11

MONITOR
712
580
762
625
Total
count turtles
17
1
11

MONITOR
714
640
764
685
Attd.
attendance
17
1
11

TEXTBOX
733
624
749
642
|
12
0.0
1

TEXTBOX
735
685
751
703
|
12
0.0
1

MONITOR
782
640
840
685
% Attd.
Attendance / (count turtles) * 100
2
1
11

MONITOR
783
700
843
745
% Work
(count turtles - Attendance) / (count turtles) * 100
2
1
11

TEXTBOX
763
656
784
674
-->
12
0.0
1

TEXTBOX
766
715
791
733
-->
12
0.0
1

MONITOR
780
580
837
625
% int.
((count turtles - drones ) / drones) * 100
3
1
11

TEXTBOX
760
595
785
613
-->
12
14.0
1

MONITOR
905
695
955
740
Min
min serie_working
17
1
11

MONITOR
1020
695
1070
740
max
max serie_working
17
1
11

MONITOR
960
695
1017
740
avg
mean serie_working
2
1
11

SLIDER
280
455
517
488
Battery_Consumption_SD
Battery_Consumption_SD
0
4
0.1
0.1
1
NIL
HORIZONTAL

PLOT
1075
265
1390
465
Working
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
"Working" 1.0 0 -16777216 true "" "plot (count turtles - attendance)"
"Limiar" 1.0 0 -8053223 true "" "plot overcrowding-threshold1"
"Total" 1.0 0 -14439633 true "" "plot count turtles"

PLOT
1075
470
1590
780
Rcharging Place Attendance
Time
Attendance
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot  attendance\n"
"pen-1" 1.0 0 -5298144 true "" "plot overcrowding-threshold1"

@#$#@#$#@
## ACKNOWLEDGMENT


Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2007 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.
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

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Experiments 2025" repetitions="10" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <postRun>createreport</postRun>
    <timeLimit steps="1500"/>
    <exitCondition>not any? turtles</exitCondition>
    <metric>count turtles</metric>
    <metric>ticks</metric>
    <enumeratedValueSet variable="Battery_Gain">
      <value value="50"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Policy">
      <value value="0"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Battery_consumption">
      <value value="10"/>
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-strategies">
      <value value="2"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p2_upperlimit">
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memory-size">
      <value value="2"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p2_lowerlimit">
      <value value="25"/>
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drones">
      <value value="50"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Battery_Consumption_SD">
      <value value="0"/>
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overcrowding-threshold">
      <value value="30"/>
      <value value="60"/>
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
1
@#$#@#$#@
