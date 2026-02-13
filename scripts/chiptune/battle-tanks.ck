// Solo Factory — Battle City / Tanks Theme
// Military march feel, Dm/Am, steady march tempo
// Run: chuck battle-tanks.ck or chuck battle-tanks.ck:0.1

0.15 => float masterVol;
if (me.args() > 0) Std.atof(me.arg(0)) => masterVol;

120 => float bpm;
(60.0 / bpm)::second => dur beat;
beat / 4 => dur sixteenth;

fun float note(string n) {
    if (n == "_") return 0.0;
    if (n == "A2") return 110.00;
    if (n == "C3") return 130.81;
    if (n == "D3") return 146.83;
    if (n == "E3") return 164.81;
    if (n == "F3") return 174.61;
    if (n == "G3") return 196.00;
    if (n == "A3") return 220.00;
    if (n == "Bb3") return 233.08;
    if (n == "C4") return 261.63;
    if (n == "D4") return 293.66;
    if (n == "E4") return 329.63;
    if (n == "F4") return 349.23;
    if (n == "G4") return 392.00;
    if (n == "A4") return 440.00;
    if (n == "Bb4") return 466.16;
    if (n == "C5") return 523.25;
    if (n == "D5") return 587.33;
    if (n == "E5") return 659.25;
    if (n == "F5") return 698.46;
    return 0.0;
}

// ── Channels (military, sharp) ──
PulseOsc melody => ADSR melEnv => Gain melGain => dac;
0.5 => melody.width;
melEnv.set(2::ms, 50::ms, 0.65, 60::ms);
masterVol * 0.45 => melGain.gain;

PulseOsc bass => ADSR basEnv => Gain basGain => dac;
0.5 => bass.width;
basEnv.set(2::ms, 30::ms, 0.8, 40::ms);
masterVol * 0.4 => basGain.gain;

TriOsc arp => ADSR arpEnv => Gain arpGain => dac;
arpEnv.set(2::ms, 35::ms, 0.4, 50::ms);
masterVol * 0.2 => arpGain.gain;

// Snare-like (high noise burst)
Noise snare => ADSR snareEnv => HPF snareHpf => Gain snareGain => dac;
snareEnv.set(1::ms, 30::ms, 0.0, 10::ms);
snareHpf.freq(700);
masterVol * 0.22 => snareGain.gain;

// Kick-like (low noise thud)
Noise kick => ADSR kickEnv => LPF kickLpf => Gain kickGain => dac;
kickEnv.set(1::ms, 40::ms, 0.0, 15::ms);
kickLpf.freq(300);
masterVol * 0.3 => kickGain.gain;

Noise hihat => ADSR hatEnv => HPF hatHpf => Gain hatGain => dac;
hatEnv.set(1::ms, 6::ms, 0.0, 4::ms);
hatHpf.freq(5000);
masterVol * 0.08 => hatGain.gain;


// ═══════════════════════════════════════
// SECTION A: March Forward (Dm, military precision)
// ═══════════════════════════════════════

["D4","_","D4","F4", "A4","_","A4","G4",
 "F4","_","F4","E4", "D4","_","D4","_",
 "D4","_","D4","F4", "A4","_","C5","Bb4",
 "A4","G4","F4","E4", "D4","_","_","_"] @=> string melA[];

["D3","_","D3","_", "A2","_","A2","_",
 "F3","_","F3","_", "D3","_","D3","_",
 "D3","_","D3","_", "F3","_","F3","_",
 "G3","_","A3","_", "D3","_","D3","_"] @=> string basA[];

// Marching pattern: kick-snare-kick-snare
[1,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,1,0,
 1,0,0,0, 0,0,1,0, 0,0,0,0, 1,0,1,0] @=> int kickA[];

[0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0,
 0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,1] @=> int snareA[];

[0,0,1,0, 0,0,0,0, 1,0,0,0, 0,0,0,0,
 0,0,1,0, 0,0,0,0, 1,0,0,0, 0,0,0,0] @=> int hatA[];


// ═══════════════════════════════════════
// SECTION B: Under Fire (Am, tense)
// ═══════════════════════════════════════

["A4","_","A4","C5", "E5","_","D5","C5",
 "A4","_","G4","A4", "Bb4","_","A4","_",
 "F4","_","F4","A4", "C5","_","Bb4","A4",
 "G4","F4","E4","D4", "E4","_","_","_"] @=> string melB[];

["A2","_","A2","_", "C3","_","C3","_",
 "A2","_","A2","_", "G3","_","G3","_",
 "F3","_","F3","_", "C3","_","C3","_",
 "D3","_","E3","_", "A2","_","A2","_"] @=> string basB[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0,
 1,0,0,1, 0,0,1,0, 1,0,1,0, 1,0,0,1] @=> int kickB[];

[0,0,1,0, 0,1,0,0, 0,0,1,0, 0,1,0,0,
 0,0,1,0, 0,1,0,0, 0,1,0,1, 0,0,1,0] @=> int snareB[];

[0,1,0,0, 1,0,0,1, 0,1,0,0, 1,0,0,1,
 0,1,0,0, 1,0,0,1, 0,0,1,0, 0,1,0,0] @=> int hatB[];


// ═══════════════════════════════════════
// SECTION C: Victory March (F major, triumphant)
// ═══════════════════════════════════════

["F4","A4","C5","F5", "E5","C5","A4","_",
 "D5","F5","E5","D5", "C5","A4","F4","_",
 "F4","G4","A4","C5", "D5","E5","F5","E5",
 "D5","C5","A4","G4", "F4","_","F4","_"] @=> string melC[];

["F3","_","F3","_", "C3","_","C3","_",
 "D3","_","D3","_", "A2","_","A2","_",
 "F3","_","F3","_", "C3","_","C3","_",
 "D3","_","E3","_", "F3","_","F3","_"] @=> string basC[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0,
 1,0,0,1, 0,0,1,0, 1,0,1,1, 1,0,1,1] @=> int kickC[];

[0,0,1,0, 0,1,0,0, 0,0,1,0, 0,1,0,0,
 0,0,1,0, 0,1,0,0, 0,0,0,0, 0,1,0,0] @=> int snareC[];

[0,0,0,1, 0,0,0,1, 0,0,0,1, 0,0,0,1,
 0,0,0,1, 0,0,0,1, 0,1,0,1, 0,0,0,0] @=> int hatC[];


// ═══════════════════════════════════════
// Arpeggio
// ═══════════════════════════════════════

["D3","F3","A3","D4", "F3","A3","D4","F4",
 "A2","C3","E3","A3", "C3","E3","A3","C4",
 "F3","A3","C4","F4", "A3","C4","F4","A4",
 "G3","Bb3","D4","G4", "A3","D4","F4","A4"] @=> string arpA[];


// ═══════════════════════════════════════
// Play functions
// ═══════════════════════════════════════

fun void playMel(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => melody.freq;
    melEnv.keyOn();
    d - 4::ms => now;
    melEnv.keyOff();
    4::ms => now;
}

fun void playBas(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => bass.freq;
    basEnv.keyOn();
    d - 3::ms => now;
    basEnv.keyOff();
    3::ms => now;
}

fun void playArp(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => arp.freq;
    arpEnv.keyOn();
    d - 3::ms => now;
    arpEnv.keyOff();
    3::ms => now;
}

fun void doKick(dur d) {
    kickEnv.keyOn();
    d - 2::ms => now;
    kickEnv.keyOff();
    2::ms => now;
}

fun void doSnare(dur d) {
    snareEnv.keyOn();
    d - 2::ms => now;
    snareEnv.keyOff();
    2::ms => now;
}

fun void doHat(dur d) {
    hatEnv.keyOn();
    d - 1::ms => now;
    hatEnv.keyOff();
    1::ms => now;
}

fun void playSection(string mel[], string bas[], string arps[],
                     int kicks[], int snares[], int hats[], int repeats) {
    for (0 => int rep; rep < repeats; rep++) {
        for (0 => int i; i < mel.size(); i++) {
            bas[i % bas.size()] => string bNote;
            arps[i % arps.size()] => string aNote;
            i % kicks.size() => int kIdx;
            i % snares.size() => int sIdx;
            i % hats.size() => int hIdx;
            spork ~ playBas(bNote, sixteenth);
            spork ~ playArp(aNote, sixteenth);
            if (kicks[kIdx] == 1) spork ~ doKick(sixteenth);
            if (snares[sIdx] == 1) spork ~ doSnare(sixteenth);
            if (hats[hIdx] == 1) spork ~ doHat(sixteenth);
            playMel(mel[i], sixteenth);
        }
    }
}

// ═══════════════════════════════════════
// Main loop: March → Under Fire → Victory
// ═══════════════════════════════════════

<<< "Battle Tanks started |", bpm, "BPM |", masterVol, "vol" >>>;

while (true) {
    playSection(melA, basA, arpA, kickA, snareA, hatA, 2);
    playSection(melB, basB, arpA, kickB, snareB, hatB, 2);
    playSection(melC, basC, arpA, kickC, snareC, hatC, 2);
    playSection(melB, basB, arpA, kickB, snareB, hatB, 1);
    playSection(melA, basA, arpA, kickA, snareA, hatA, 1);
}
