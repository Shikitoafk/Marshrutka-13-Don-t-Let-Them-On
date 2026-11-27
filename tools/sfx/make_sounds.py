"""Процедурные звуки для Marshrutka 13. Всё синтезируется с нуля (numpy/scipy), без чужих записей.
Выход: WAV 44.1 кГц моно в ./out, затем конвертация в OGG и MP3 снаружи (ffmpeg)."""
import os
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(1313)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def brown(sec):
    x = np.cumsum(noise(sec))
    x = signal.sosfilt(signal.butter(1, 20, "hp", fs=SR, output="sos"), x)
    return x / (np.max(np.abs(x)) + 1e-9)


def bp(x, lo, hi, order=4):
    return signal.sosfilt(signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x)


def lp(x, f, order=4):
    return signal.sosfilt(signal.butter(order, f, "lowpass", fs=SR, output="sos"), x)


def hp(x, f, order=4):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x)


def env_exp(sec, decay, attack=0.002):
    tt = t(sec)
    e = np.exp(-tt / decay)
    a = np.clip(tt / attack, 0, 1)
    return e * a


def reverb(x, seconds=1.8, wet=0.3, damp=3000):
    x = np.array(x, dtype=np.float64)
    taper = min(len(x) // 4, int(SR * 0.03))
    x[-taper:] *= np.linspace(1, 0, taper)  # без щелчка, если исходник обрезан на звучащей ноте
    ir_len = int(SR * seconds)
    ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (SR * seconds / 6))
    ir = lp(ir, damp, 2)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + ir_len
    y = np.zeros(n)
    conv = signal.fftconvolve(x, ir)
    y[: min(n, len(conv))] = conv[:n]
    dry = np.concatenate([x, np.zeros(ir_len)])
    return (1 - wet) * dry + wet * y


def make_loop(x, fade=0.5):
    """Бесшовная петля: хвост плавно перекрываем с началом."""
    n = int(SR * fade)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    w = np.linspace(0, 1, n)
    blended = tail * (1 - w) + head * w
    return np.concatenate([body, blended])


def norm(x, peak_db=-1.0):
    x = x - np.mean(x)
    p = np.max(np.abs(x)) + 1e-9
    return x / p * (10 ** (peak_db / 20))


LOOPS = {"RadioStatic", "Ambience", "Heartbeat", "Engine", "Whispers", "Music"}


def save(name, x, peak_db=-1.0):
    x = np.asarray(x, dtype=np.float64)
    if name not in LOOPS:
        fade = int(SR * 0.04)
        x[-fade:] *= np.linspace(1, 0, fade)
    x = norm(x, peak_db)
    wavfile.write(os.path.join(OUT, f"{name}.wav"), SR, (x * 32767).astype(np.int16))
    print(f"{name}: {len(x)/SR:.2f}s")


# 1. Шипение радио (петля 4 с): полосовой шум + треск + «уплывающая» станция
def radio_static():
    d = 4.5
    n = bp(noise(d), 400, 5000) * 0.5
    crackle = (rng.random(int(SR * d)) > 0.9993).astype(float) * rng.uniform(0.5, 1.5, int(SR * d))
    crackle = signal.lfilter([1], [1, -0.97], crackle)
    tt = t(d)
    sweep = np.sin(2 * np.pi * (900 + 300 * np.sin(2 * np.pi * 0.23 * tt)) * tt) * 0.05
    sweep *= (0.5 + 0.5 * np.sin(2 * np.pi * 0.4 * tt)) ** 2
    am = 0.7 + 0.3 * lp(noise(d), 6, 2) / 0.3
    return make_loop((n * np.clip(am, 0.2, 1.3) + crackle * 0.6 + sweep), 0.5)


# 2. Хоррор-эмбиент (петля 30 с): низкий бьющийся гул + ветер + металлические «вздохи»
def ambience():
    d = 31
    tt = t(d)
    drone = (np.sin(2 * np.pi * 55 * tt) + 0.8 * np.sin(2 * np.pi * 55.8 * tt) + 0.5 * np.sin(2 * np.pi * 82.4 * tt))
    drone = np.tanh(drone * 1.8)  # гармоники 110–400 Гц: гул слышен и на маленьких динамиках
    drone *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * tt)
    wind = lp(brown(d), 600) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * tt + 1))
    wind += bp(noise(d), 250, 1400, 2) * 0.12 * (0.4 + 0.6 * np.sin(2 * np.pi * 0.11 * tt) ** 2)
    swells = np.zeros_like(tt)
    for start, f in [(4, 311), (13, 233), (22, 349)]:
        seg = (tt >= start) & (tt < start + 6)
        local = tt[seg] - start
        shape = np.sin(np.pi * local / 6) ** 3
        swells[seg] += shape * (np.sin(2 * np.pi * f * local) + 0.5 * np.sin(2 * np.pi * f * 2.76 * local)) * 0.25
    x = drone * 0.5 + wind * 0.6 + swells
    x = reverb(x, 3.0, 0.35)[: int(SR * d)]
    return make_loop(x, 1.0)


# 3. Сердцебиение (петля, ~70 уд/мин): «тук-тук»
def heartbeat():
    period = 60 / 70
    out = np.zeros(int(SR * period))

    def thump(f0, dur, amp):
        tt = t(dur)
        f = f0 * (1 + 0.6 * np.exp(-tt / 0.02))
        ph = 2 * np.pi * np.cumsum(f) / SR
        body = np.sin(ph) * env_exp(dur, 0.06, 0.004)
        thud = bp(noise(dur), 150, 700, 2) * env_exp(dur, 0.03, 0.002) * 2.2  # «удар» в груди — слышно и на телефоне
        return (body + thud) * amp

    a = thump(70, 0.25, 1.0)
    b = thump(62, 0.25, 0.7)
    out[: len(a)] += a
    off = int(SR * 0.28)
    out[off: off + len(b)] += b
    out = np.tanh(out * 2.5)
    return lp(out, 650)


# 4. «Динь» остановки: два тона колокольчика
def stop_chime():
    d = 2.2
    out = np.zeros(int(SR * d))
    for start, f in [(0.0, 659.25), (0.35, 523.25)]:
        tt = np.arange(len(out) - int(SR * start)) / SR
        tone = sum(a * np.sin(2 * np.pi * f * m * tt) * np.exp(-tt / dec)
                   for m, a, dec in [(1, 1, 1.2), (2.0, 0.35, 0.6), (3.01, 0.15, 0.35), (4.2, 0.08, 0.2)])
        out[int(SR * start):] += tone * np.clip(tt / 0.003, 0, 1)
    return reverb(out, 1.2, 0.2)[: int(SR * 2.6)]


# 5. Стук в окно: три удара костяшками
def knock():
    d = 1.6
    out = np.zeros(int(SR * d))
    for i, start in enumerate([0.0, 0.22, 0.44]):
        dur = 0.18
        burst = noise(dur) * env_exp(dur, 0.012, 0.0005)
        body = bp(burst, 250, 900, 2) * 2.5 + bp(burst, 1800, 3500, 2) * 0.6
        tt = t(dur)
        body += np.sin(2 * np.pi * (180 - i * 10) * tt) * env_exp(dur, 0.03) * 0.5
        s = int(SR * start)
        out[s: s + len(body)] += body * (1.0 - 0.1 * i)
    return reverb(out, 0.8, 0.15)[: int(SR * d)]


# 6. Удар по металлической крыше
def bang():
    d = 2.8
    tt = t(d)
    thud = np.sin(2 * np.pi * 60 * tt * (1 + 0.5 * np.exp(-tt / 0.03))) * env_exp(d, 0.15)
    metal = sum(np.sin(2 * np.pi * f * tt + rng.random() * 6) * np.exp(-tt / dec) * a
                for f, dec, a in [(187, 1.2, 0.5), (311, 0.9, 0.4), (523, 0.6, 0.3), (877, 0.4, 0.2), (1433, 0.25, 0.15)])
    trans = hp(noise(d), 1500) * env_exp(d, 0.02) * 0.8
    return reverb(thud * 1.2 + metal + trans, 1.5, 0.25)[: int(SR * 3.2)]


# 7. Двигатель на холостых (петля 4 с; высоту меняет PlaybackSpeed в Roblox)
def engine():
    d = 4.5
    tt = t(d)
    f0 = 28 * (1 + 0.01 * np.sin(2 * np.pi * 0.7 * tt))
    ph = 2 * np.pi * np.cumsum(f0) / SR
    x = sum(np.sin(k * ph) / k ** 0.8 for k in range(1, 14))
    x *= 1 + 0.25 * np.sin(ph / 2)  # «неровная» работа цилиндров
    x = lp(x, 900) + lp(brown(d), 300) * 0.5
    return make_loop(x, 0.4)


# 8. Пневмодвери: открыть (пшш + клац) и закрыть (клац + короткое пшш)
def hiss(dur, decay):
    x = hp(noise(dur), 2500) * env_exp(dur, decay, 0.01)
    fade = int(SR * 0.08)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def clunk():
    dur = 0.35
    tt = t(dur)
    return (np.sin(2 * np.pi * 90 * tt) * env_exp(dur, 0.05) + bp(noise(dur), 300, 1500) * env_exp(dur, 0.02) * 0.8)


def door_open():
    x = np.zeros(int(SR * 1.8))
    h = hiss(1.2, 0.45) * 0.7
    x[: len(h)] += h
    c = clunk()
    s = int(SR * 0.9)
    x[s: s + len(c)] += c
    return x


def door_close():
    x = np.zeros(int(SR * 1.2))
    c = clunk()
    x[: len(c)] += c * 1.2
    h = hiss(0.6, 0.15) * 0.5
    s = int(SR * 0.15)
    x[s: s + len(h)] += h
    return x


# 9. Гудок маршрутки: два расстроенных тона
def horn():
    d = 0.9
    tt = t(d)
    x = signal.square(2 * np.pi * 330 * tt) + signal.square(2 * np.pi * 415 * tt)
    x = lp(x, 2200) * np.clip(tt / 0.02, 0, 1) * np.clip((d - tt) / 0.06, 0, 1)
    return reverb(x, 0.6, 0.15)[: int(SR * 1.1)]


# 10. Старый телефон: звонок-трель
def phone():
    d = 4.0
    tt = t(d)
    bell = sum(np.sin(2 * np.pi * f * tt) * a for f, a in [(1150, 1), (2300, 0.3), (1720, 0.4)])
    trill = (np.sin(2 * np.pi * 20 * tt) > 0).astype(float)
    gate = ((tt % 3.0) < 1.6).astype(float)
    gate = lp(gate, 60, 2)
    return reverb(bell * trill * gate * 0.6, 0.7, 0.2)[: int(SR * d)]


# 11. Шёпот (петля 8 с): шум через «формантные» фильтры со слоговыми огибающими, 3 голоса
def whispers():
    d = 8.5
    out = np.zeros(int(SR * d))
    for v in range(3):
        n = noise(d)
        voice = np.zeros_like(n)
        pos = rng.uniform(0, 0.4)
        while pos < d - 0.3:
            syl = rng.uniform(0.08, 0.22)
            f1, f2 = rng.uniform(400, 900), rng.uniform(1200, 2800)
            s, e = int(SR * pos), int(SR * (pos + syl))
            seg = n[s:e]
            shaped = bp(seg, f1 * 0.8, f1 * 1.2, 2) + bp(seg, f2 * 0.85, f2 * 1.15, 2) * 0.7 + hp(seg, 5000, 2) * 0.3
            voice[s:e] += shaped * np.hanning(e - s)
            pos += syl + rng.uniform(0.02, 0.35) + (rng.uniform(0.4, 1.0) if rng.random() < 0.15 else 0)
        out += voice * (0.6 + 0.2 * v)
    out = reverb(out, 2.5, 0.45)[: int(SR * d)]
    return make_loop(out, 0.5)


# 12. Скример: визг с понижающимся тоном + удар + искажение
def jumpscare():
    d = 1.6
    tt = t(d)
    f = 2400 * np.exp(-tt / 0.9) + 500
    ph = 2 * np.pi * np.cumsum(f) / SR
    screech = sum(signal.sawtooth(ph * r) for r in (1, 1.013, 0.987, 1.5))
    screech += hp(noise(d), 1200) * 1.5
    screech = np.tanh(screech * 1.5) * np.clip(tt / 0.01, 0, 1) * np.exp(-tt / 1.0)
    screech *= np.clip((d - tt) / 0.25, 0, 1)  # хвост визга уходит за 0.25 с, а не обрывается
    boom = np.sin(2 * np.pi * 45 * tt * (1 + np.exp(-tt / 0.05))) * env_exp(d, 0.35) * 2
    return reverb(screech + boom, 1.0, 0.2)[: int(SR * 2.0)]


# 13. Жуткая музыка (петля 32 с): «музыкальная шкатулка» в миноре + низкий пэд
def music():
    bpm = 60
    beat = 60 / bpm
    d = 32
    out = np.zeros(int(SR * (d + 3)))
    # ля минор с тритоном; ноты в герцах
    A3, C4, D4, Ds4, E4, F4, G4, A4, B4, C5, E5 = 220, 261.6, 293.7, 311.1, 329.6, 349.2, 392, 440, 493.9, 523.3, 659.3
    melody = [A4, C5, E5, Ds4, None, A4, B4, F4, None, E4, C5, B4, A4, None, Ds4, E4,
              A4, C5, E5, F4, None, E5, Ds4, D4, None, C4, B4, A4, Ds4, None, E4, None]
    for i, f in enumerate(melody):
        if f is None:
            continue
        dur = 2.8
        tt = t(dur)
        detune = 1 + rng.uniform(-0.004, 0.004)
        note = sum(a * np.sin(2 * np.pi * f * detune * m * tt) * np.exp(-tt / dec)
                   for m, a, dec in [(1, 1, 1.4), (3.0, 0.25, 0.4), (5.4, 0.1, 0.15)])
        s = int(SR * i * beat)
        out[s: s + len(note)] += note * 0.5 * np.clip(tt / 0.002, 0, 1)
    tt = t(d + 3)
    pad = (np.sin(2 * np.pi * A3 / 2 * tt) + 0.6 * np.sin(2 * np.pi * (A3 / 2) * 1.414 * tt)) * 0.15
    pad *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.03 * tt)
    out += lp(pad, 400)
    out = reverb(out, 3.0, 0.4)[: int(SR * (d + 1))]
    return make_loop(out, 1.0)


SOUNDS = {
    "RadioStatic": radio_static,
    "Ambience": ambience,
    "Heartbeat": heartbeat,
    "StopChime": stop_chime,
    "Knock": knock,
    "Bang": bang,
    "Engine": engine,
    "DoorOpen": door_open,
    "DoorClose": door_close,
    "Horn": horn,
    "PhoneRing": phone,
    "Whispers": whispers,
    "Jumpscare": jumpscare,
    "Music": music,
}

if __name__ == "__main__":
    for name, fn in SOUNDS.items():
        save(name, fn(), -1.0 if name != "Ambience" else -3.0)
