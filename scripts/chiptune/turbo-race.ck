// Solo Factory — Turbo Racing Theme
// Fast-paced, high energy, synth arpeggios, driving beat
// Run: chuck turbo-race.ck or chuck turbo-race.ck:0.1

0.15 => float masterVol;
if (me.args() > 0) Std.atof(me.arg(0)) => masterVol;

170 => float bpm;
(60.0 / bpm)::second => dur beat;
beat / 4 => dur sixteenth;

fun float note(string n) {
    if (n == "_") return 0.0;
    if (n == "E2") return 82.41;
    if (n == "A2") return 110.00;
    if (n == "B2") return 123.47;
    if (n == "C3") return 130.81;
    if (n == "D3") return 146.83;
    if (n == "E3") return 164.81;
    if (n == "F#3") return 185.00;
    if (n == "G3") return 196.00;
    if (n == "A3") return 220.00;
    if (n == "B3") return 246.94;
    if (n == "C4") return 261.63;
    if (n == "D4") return 293.66;
    if (n == "E4") return 329.63;
    if (n == "F#4") return 369.99;
    if (n == "G4") return 392.00;
    if (n == "A4") return 440.00;
    if (n == "B4") return 493.88;
    if (n == "C5") return 523.25;
    if (n == "D5") return 587.33;
    if (n == "E5") return 659.25;
    if (n == "F#5") return 739.99;
    if (n == "G5") return 783.99;
    if (n == "A5") return 880.00;
    return 0.0;
}

// ── Channels (bright, fast) ──
PulseOsc melody => ADSR melEnv => Gain melGain => dac;
0.25 => melody.width;
melEnv.set(2::ms, 30::ms, 0.5, 40::ms);
masterVol * 0.45 => melGain.gain;

PulseOsc bass => ADSR basEnv => Gain basGain => dac;
0.5 => bass.width;
basEnv.set(2::ms, 20::ms, 0.7, 30::ms);
masterVol * 0.35 => basGain.gain;

// Fast arpeggio channel (triangle for softer high arps)
TriOsc arp => ADSR arpEnv => Gain arpGain => dac;
arpEnv.set(1::ms, 25::ms, 0.3, 30::ms);
masterVol * 0.25 => arpGain.gain;

Noise noiz => ADSR drumEnv => HPF drumHpf => Gain drumGain => dac;
drumEnv.set(1::ms, 18::ms, 0.0, 8::ms);
drumHpf.freq(800);
masterVol * 0.2 => drumGain.gain;

Noise hihat => ADSR hatEnv => HPF hatHpf => Gain hatGain => dac;
hatEnv.set(1::ms, 5::ms, 0.0, 3::ms);
hatHpf.freq(6000);
masterVol * 0.1 => hatGain.gain;


// ═══════════════════════════════════════
// SECTION A: Straightaway (E major, fast arpeggios)
// ═══════════════════════════════════════

["E5","B4","E5","G5", "F#5","E5","D5","B4",
 "E5","F#5","G5","A5","G5","F#5","E5","D5",
 "C5","E5","G5","E5", "D5","B4","A4","B4",
 "E5","D5","B4","A4", "G4","A4","B4","_"] @=> string melA[];

["E2","_","E2","_", "E2","_","E2","_",
 "A2","_","A2","_", "A2","_","A2","_",
 "C3","_","C3","_", "D3","_","D3","_",
 "E2","_","E2","_", "B2","_","E2","_"] @=> string basA[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0,
 1,0,0,1, 0,0,1,0, 1,0,1,0, 1,0,1,0] @=> int drumA[];

[0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1,
 0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1] @=> int hatA[];


// ═══════════════════════════════════════
// SECTION B: Nitro Boost (A major, rising energy)
// ═══════════════════════════════════════

["A4","C5","E5","A5", "G5","E5","C5","A4",
 "B4","D5","F#5","D5","B4","A4","F#4","_",
 "A4","B4","C5","D5", "E5","F#5","G5","A5",
 "G5","E5","D5","C5", "B4","A4","_","_"] @=> string melB[];

["A2","_","A2","_", "E2","_","E2","_",
 "B2","_","B2","_", "D3","_","D3","_",
 "A2","_","A2","_", "C3","_","C3","_",
 "D3","_","E3","_", "A2","_","A2","_"] @=> string basB[];

[1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0,
 1,0,1,0, 1,0,1,0, 1,1,0,1, 1,0,1,1] @=> int drumB[];

[0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1,
 0,1,0,1, 0,1,0,1, 1,0,1,0, 0,1,0,1] @=> int hatB[];


// ═══════════════════════════════════════
// SECTION C: Final Lap (D major, max intensity)
// ═══════════════════════════════════════

["D5","F#5","A5","F#5","D5","A4","F#4","A4",
 "D5","E5","F#5","G5","A5","G5","F#5","E5",
 "B4","D5","F#5","A5","G5","F#5","E5","D5",
 "E5","F#5","G5","A5","B4","D5","A5","_"] @=> string melC[];

["D3","_","D3","_", "A2","_","A2","_",
 "D3","_","D3","_", "G3","_","G3","_",
 "B2","_","B2","_", "D3","_","D3","_",
 "E3","_","A2","_", "D3","_","D3","_"] @=> string basC[];

[1,0,1,0, 1,0,1,1, 0,1,0,1, 1,0,1,0,
 1,0,1,0, 1,0,1,1, 1,0,1,1, 1,1,1,1] @=> int drumC[];

[1,1,0,1, 0,1,1,0, 1,0,1,1, 0,1,0,1,
 1,1,0,1, 0,1,1,0, 1,1,1,0, 1,0,1,0] @=> int hatC[];


// ═══════════════════════════════════════
// Arpeggio patterns (fast cascading)
// ═══════════════════════════════════════

["E3","G3","B3","E4", "G3","B3","E4","G4",
 "A3","C4","E4","A4", "C4","E4","A4","C5",
 "D3","F#3","A3","D4","F#3","A3","D4","F#4",
 "B3","D4","F#4","B4","D4","F#4","B4","D5"] @=> string arpA[];


// ═══════════════════════════════════════
// Play functions
// ═══════════════════════════════════════

fun void playMel(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => melody.freq;
    melEnv.keyOn();
    d - 3::ms => now;
    melEnv.keyOff();
    3::ms => now;
}

fun void playBas(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => bass.freq;
    basEnv.keyOn();
    d - 2::ms => now;
    basEnv.keyOff();
    2::ms => now;
}

fun void playArp(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => arp.freq;
    arpEnv.keyOn();
    d - 2::ms => now;
    arpEnv.keyOff();
    2::ms => now;
}

fun void kick(dur d) {
    drumEnv.keyOn();
    d - 2::ms => now;
    drumEnv.keyOff();
    2::ms => now;
}

fun void hat(dur d) {
    hatEnv.keyOn();
    d - 1::ms => now;
    hatEnv.keyOff();
    1::ms => now;
}

fun void playSection(string mel[], string bas[], string arps[],
                     int drums[], int hats[], int repeats) {
    for (0 => int rep; rep < repeats; rep++) {
        for (0 => int i; i < mel.size(); i++) {
            bas[i % bas.size()] => string bNote;
            arps[i % arps.size()] => string aNote;
            i % drums.size() => int dIdx;
            i % hats.size() => int hIdx;
            spork ~ playBas(bNote, sixteenth);
            spork ~ playArp(aNote, sixteenth);
            if (drums[dIdx] == 1) spork ~ kick(sixteenth);
            if (hats[hIdx] == 1) spork ~ hat(sixteenth);
            playMel(mel[i], sixteenth);
        }
    }
}

// ═══════════════════════════════════════
// Main loop: Straightaway → Nitro → Final Lap
// ═══════════════════════════════════════

<<< "Turbo Race started |", bpm, "BPM |", masterVol, "vol" >>>;

while (true) {
    playSection(melA, basA, arpA, drumA, hatA, 2);
    playSection(melB, basB, arpA, drumB, hatB, 2);
    playSection(melC, basC, arpA, drumC, hatC, 2);
    playSection(melB, basB, arpA, drumB, hatB, 1);
}
