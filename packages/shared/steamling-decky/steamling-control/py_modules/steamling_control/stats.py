import threading
from pathlib import Path

# Plain sysfs/procfs reads only, no processes spawned: the panel asks every couple of seconds
# while the monitor is shown.
CPUFREQ = Path("/sys/devices/system/cpu/cpufreq")
DEVFREQ = Path("/sys/class/devfreq")
THERMAL = Path("/sys/class/thermal")
POWER_SUPPLY = Path("/sys/class/power_supply")
HWMON = Path("/sys/class/hwmon")
PROC_STAT = Path("/proc/stat")
MEMINFO = Path("/proc/meminfo")

_lock = threading.Lock()
_last_cpu = {"total": None, "idle": None}


def _read(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def _int(path):
    try:
        return int(_read(path))
    except ValueError:
        return None


def cpu_clusters(base=CPUFREQ):
    # One entry per frequency domain (little, big, prime), current and top clock in MHz.
    out = []
    for policy in sorted(base.glob("policy[0-9]*"), key=lambda p: int(p.name[6:])):
        cur = _int(policy / "scaling_cur_freq")
        top = _int(policy / "cpuinfo_max_freq")
        if cur is None:
            continue
        out.append({"cpus": _read(policy / "related_cpus"), "mhz": cur // 1000, "maxMhz": (top or 0) // 1000})
    return out


def cpu_load(stat_text):
    """Busy percent since the previous call; None on the first one."""
    line = next((l for l in stat_text.splitlines() if l.startswith("cpu ")), "")
    fields = [int(x) for x in line.split()[1:] if x.isdigit()]
    if len(fields) < 5:
        return None
    idle = fields[3] + fields[4]
    total = sum(fields[:8])
    with _lock:
        prev_total, prev_idle = _last_cpu["total"], _last_cpu["idle"]
        _last_cpu["total"], _last_cpu["idle"] = total, idle
    if prev_total is None or total <= prev_total:
        return None
    return round(100 * (1 - (idle - prev_idle) / (total - prev_total)))


def gpu(base=DEVFREQ):
    for dev in sorted(base.glob("*")):
        if "gpu" not in dev.name:
            continue
        cur = _int(dev / "cur_freq")
        top = _int(dev / "max_freq")
        if cur is not None:
            return {"mhz": cur // 1000000, "maxMhz": (top or 0) // 1000000}
    return None


_zones = {}


def _cpu_gpu_zones(base):
    """(kind, temp path) for the cpu*/gpu* zones, found once per base and then reused.

    The zones are fixed once the SoC's sensors have probed, and the others include the PMIC's
    board sensors, whose temp read starts an ADC conversion, so neither the scan nor those reads
    belong in a two-second loop. An empty result is not kept, in case the sensors are still
    probing."""
    zones = _zones.get(base)
    if zones is None:
        zones = []
        for zone in sorted(base.glob("thermal_zone*")):
            kind = _read(zone / "type")
            group = "cpu" if kind.startswith("cpu") else "gpu" if kind.startswith("gpu") else None
            if group:
                zones.append((group, zone / "temp"))
        if zones:
            _zones[base] = zones
    return zones


def temperatures(base=THERMAL):
    # The hottest zone of each kind, in °C. Zone names differ per SoC, but cpu*/gpu* covers them.
    hottest = {}
    for group, path in _cpu_gpu_zones(base):
        temp = _int(path)
        if temp is not None and temp > 0:
            hottest[group] = max(hottest.get(group, 0), temp)
    return {k: round(v / 1000) for k, v in hottest.items()}


def battery(base=POWER_SUPPLY):
    for ps in sorted(base.glob("*")):
        if _read(ps / "type") != "Battery":
            continue
        watts = None
        power = _int(ps / "power_now")
        current, voltage = _int(ps / "current_now"), _int(ps / "voltage_now")
        if current is not None and voltage is not None:
            watts = abs(current) * voltage / 1e12
        elif power is not None:
            watts = abs(power) / 1e6
        temp = _int(ps / "temp")
        return {
            "percent": _int(ps / "capacity"),
            "status": _read(ps / "status"),
            "watts": round(watts, 1) if watts is not None else None,
            "tempC": round(temp / 10) if temp is not None else None,
        }
    return None


def memory(meminfo_text):
    values = {}
    for line in meminfo_text.splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if parts and parts[0].isdigit():
            values[key] = int(parts[0])
    total, available = values.get("MemTotal"), values.get("MemAvailable")
    if not total or available is None:
        return None
    return {"usedMb": (total - available) // 1024, "totalMb": total // 1024}


def fan(base=HWMON):
    for mon in sorted(base.glob("hwmon*")):
        rpm = _int(mon / "fan1_input")
        pwm = _int(mon / "pwm1")
        if rpm is not None or pwm is not None:
            return {"rpm": rpm, "percent": round(100 * pwm / 255) if pwm is not None else None}
    return None


def system_stats():
    return {
        "cpu": {"load": cpu_load(_read(PROC_STAT)), "clusters": cpu_clusters()},
        "gpu": gpu(),
        "temps": temperatures(),
        "battery": battery(),
        "memory": memory(_read(MEMINFO)),
        "fan": fan(),
    }
