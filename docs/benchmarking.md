# Measuring changes

`steamling-bench` takes the same few measurements on the handheld before and after a change: a
new kernel, a different setting, a new build. That way you can tell whether a change helped from
numbers, not from how it feels on one evening. It's already installed. Run it over
[SSH](governor.md#remote-access) or in Konsole in desktop mode.

Every run saves one small text file in `~/steamling-bench/`. Each file starts with what was
running at the time (the Steamling version, the kernel, Mesa, the preemption model), so you can
always tell two runs apart later.

## The tests

| Command | What it measures | How long |
|---|---|---|
| `steamling-bench boot` | How long the last boot took, from power on to game mode | Instant |
| `sudo steamling-bench sleep 30` | Battery drain while asleep, and what woke the handheld | 30 minutes |
| `steamling-bench load 10` | CPU and GPU clocks, temperatures, battery power and fan while you play | 10 minutes |
| `sudo steamling-bench input 10` | How often the controller reports, and how evenly | 10 seconds |
| `steamling-bench frames` | Frame times from a MangoHud log | Instant |
| `steamling-bench info` | Just the header: what is running right now | Instant |

### Boot

Run it any time after the handheld has started. It reads this boot's log, so it only knows about
the most recent boot. Run it with `sudo` if it says it can't find gamescope.

### Sleep

Unplug the charger first: a charging battery says nothing about drain. Then:

```bash
sudo steamling-bench sleep 30
```

The handheld goes to sleep straight away and wakes itself after 30 minutes. If it can't wake
itself, it says so and waits for you instead. Add `--manual` to use the power button from the
start: it then waits for you to sleep and wake the handheld yourself.

You get the drain in percent per hour and, where the battery reports it, in milliwatts. You also
get what share of the time it actually spent asleep, and which wakeup sources fired. A long list
of wakeups, or a low asleep share, is where to look when battery life asleep is poor. The battery
percentage moves in whole steps, so sleep for at least 30 minutes; longer gives a better number.

### Load

Start the command, then start your game, and play normally:

```bash
steamling-bench load 10
```

Every second it records each CPU cluster's clock, the GPU clock, the temperatures, the fan speed
and how much power the battery is giving. At the end you get averages and peaks, plus how much of
the time the GPU spent at its top clock. A `.csv` file with every sample sits next to the result,
which any spreadsheet can chart. Ctrl-C stops it early.

Use the same game, the same scene and the same settings every time you compare. Two different
games say nothing about a kernel.

### Input

```bash
sudo steamling-bench input 10
```

Move both sticks in circles for the whole 10 seconds. It reports how many times a second the
controller sends an update and how even the gaps between updates are. The RP6's controller should
show close to 250 Hz with a tight spread. It picks the first controller nothing else holds
exclusively: InputPlumber takes the built-in pad and passes it on to Steam as another one, and
that one is what gets measured. To measure a particular device, name it, for example
`sudo steamling-bench input 10 "X-Box"`.

This measures the time between the controller's own reports, not the whole delay from your thumb
to the screen. That needs a camera.

### Frames

MangoHud can write a log of every frame's time, and `steamling-bench frames` turns that log into
average fps, 1% and 0.1% lows, the spread of frame times and a count of stutters.

To record one, open the game's **Properties** in Steam and set its **Launch Options** to:

```
MANGOHUD_CONFIG=no_display,autostart_log=5,log_duration=60,output_folder=/home/deck/steamling-bench/mangohud mangohud %command%
```

Start the game. Five seconds in, it records the next 60 seconds, without showing anything extra
on screen. Then run `steamling-bench frames`, which reads the newest log. Remove the launch options
again when you're done.

## Comparing two runs

```bash
steamling-bench list
steamling-bench compare 20261103-101500-load.txt 20261104-093000-load.txt
```

The two runs are printed side by side, with the change in percent next to each number that moved.

A sensible routine for a new kernel or setting:

1. Run the tests on the old one.
2. Install the change and reboot.
3. Run exactly the same tests again.
4. Compare.

Run each test twice. If the two runs on the same setup differ by about as much as the change
does, the change made no difference you can measure.

## Trying lazy preemption

The kernel can be told at boot, or while running, how readily it interrupts a running task for a
more urgent one. `full`, the default, is the most responsive. `lazy` interrupts less often, which
can smooth frame times. To try it until the next reboot:

```bash
echo lazy | sudo tee /sys/kernel/debug/sched/preempt
```

Then run the load and frames tests, put it back with `echo full | sudo tee
/sys/kernel/debug/sched/preempt`, and run them again. `steamling-bench info` shows the model in
use, so every result records which one it was measured with.
