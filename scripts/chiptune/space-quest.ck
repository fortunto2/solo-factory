// Solo Factory — Space Quest / Galaga Theme
// Cosmic, mysterious, wide arpeggios, space shooter vibes
// Run: chuck space-quest.ck or chuck space-quest.ck:0.1

0.15 => float masterVol;
if (me.args() > 0) Std.atof(me.arg(0)) => masterVol;

135 => float bpm;
(60.0 / bpm)::second => dur beat;
beat / 4 => dur sixteenth;

fun float note(string n) {
    if (n == "_") return 0.0;
    if (n == "C3") return 130.81;
    if (n == "D3") return 146.83;
    if (n == "Eb3") return 155.56;
    if (n == "E3") return 164.81;
    if (n == "F3") return 174.61;
    if (n == "G3") return 196.00;
    if (n == "Ab3") return 207.65;
    if (n == "A3") return 220.00;
    if (n == "Bb3") return 233.08;
    if (n == "B3") return 246.94;
    if (n == "C4") return 261.63;
    if (n == "D4") return 293.66;
    if (n == "Eb4") return 311.13;
    if (n == "E4") return 329.63;
    if (n == "F4") return 349.23;
    if (n == "G4") return 392.00;
    if (n == "Ab4") return 415.30;
    if (n == "A4") return 440.00;
    if (n == "Bb4") return 466.16;
    if (n == "B4") return 493.88;
    if (n == "C5") return 523.25;
    if (n == "D5") return 587.33;
    if (n == "Eb5") return 622.25;
    if (n == "E5") return 659.25;
    if (n == "F5") return 698.46;
    if (n == "G5") return 783.99;
    if (n == "A5") return 880.00;
    return 0.0;
}

// ── Channels (spacey, wide) ──
PulseOsc melody => ADSR melEnv => Gain melGain => dac;
0.25 => melody.width;
melEnv.set(5::ms, 60::ms, 0.5, 100::ms);
masterVol * 0.45 => melGain.gain;

PulseOsc bass => ADSR basEnv => Gain basGain => dac;
0.5 => bass.width;
basEnv.set(3::ms, 30::ms, 0.7, 50::ms);
masterVol * 0.35 => basGain.gain;

// Spacey arp (narrow pulse = thin, airy)
PulseOsc arp => ADSR arpEnv => Gain arpGain => dac;
0.1 => arp.width;
arpEnv.set(3::ms, 45::ms, 0.3, 70::ms);
masterVol * 0.2 => arpGain.gain;

Noise noiz => ADSR drumEnv => HPF drumHpf => Gain drumGain => dac;
drumEnv.set(1::ms, 20::ms, 0.0, 10::ms);
drumHpf.freq(800);
masterVol * 0.18 => drumGain.gain;

Noise hihat => ADSR hatEnv => HPF hatHpf => Gain hatGain => dac;
hatEnv.set(1::ms, 7::ms, 0.0, 4::ms);
hatHpf.freq(4500);
masterVol * 0.09 => hatGain.gain;


// ═══════════════════════════════════════
// SECTION A: Deep Space (Cm, mysterious)
// ═══════════════════════════════════════

["C5","_","Eb5","D5", "C5","_","G4","_",
 "Ab4","_","Bb4","C5","Eb5","_","D5","_",
 "C5","Eb5","G5","Eb5","C5","Bb4","Ab4","_",
 "G4","Ab4","Bb4","C5","D5","Eb5","C5","_"] @=> string melA[];

["C3","_","C3","_", "Eb3","_","Eb3","_",
 "Ab3","_","Ab3","_", "G3","_","G3","_",
 "C3","_","C3","_", "Bb3","_","Bb3","_",
 "Ab3","_","G3","_", "C3","_","C3","_"] @=> string basA[];

[1,0,0,1, 0,0,1,0, 1,0,0,0, 1,0,0,1,
 1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0] @=> int drumA[];

[0,0,1,0, 0,1,0,0, 0,0,1,0, 0,0,0,0,
 0,0,1,0, 0,1,0,0, 0,0,1,0, 0,1,0,0] @=> int hatA[];


// ═══════════════════════════════════════
// SECTION B: Asteroid Field (Fm, tense dodging)
// ═══════════════════════════════════════

["F4","Ab4","C5","Ab4","F4","C4","Ab4","_",
 "Eb4","G4","Bb4","G4","Eb4","Bb3","G4","_",
 "F4","Ab4","C5","Eb5","C5","Ab4","F4","Eb4",
 "D4","F4","Ab4","C5","Bb4","Ab4","F4","_"] @=> string melB[];

["F3","_","F3","_", "C3","_","C3","_",
 "Eb3","_","Eb3","_","Bb3","_","Bb3","_",
 "F3","_","F3","_", "Ab3","_","Ab3","_",
 "D3","_","F3","_", "Bb3","_","F3","_"] @=> string basB[];

[1,0,1,0, 0,1,0,0, 1,0,1,0, 0,1,0,0,
 1,0,1,0, 0,1,0,1, 1,0,0,1, 1,0,1,0] @=> int drumB[];

[0,1,0,0, 1,0,0,1, 0,1,0,0, 1,0,0,1,
 0,1,0,0, 1,0,1,0, 0,0,1,0, 0,1,0,0] @=> int hatB[];


// ═══════════════════════════════════════
// SECTION C: Boss Battle (Ebm, intense)
// ═══════════════════════════════════════

["Eb5","_","Eb5","F5","G5","_","F5","Eb5",
 "D5","_","C5","D5", "Eb5","_","_","_",
 "Ab4","Bb4","C5","Eb5","G5","Eb5","C5","Bb4",
 "Ab4","Bb4","C5","D5","Eb5","_","Eb5","_"] @=> string melC[];

["Eb3","_","Eb3","_","Eb3","_","Eb3","_",
 "D3","_","D3","_", "C3","_","C3","_",
 "Ab3","_","Ab3","_","G3","_","G3","_",
 "Ab3","_","Bb3","_","Eb3","_","Eb3","_"] @=> string basC[];

[1,0,0,1, 1,0,0,1, 1,0,0,1, 0,1,0,0,
 1,0,1,0, 1,0,1,0, 1,0,1,0, 1,1,1,1] @=> int drumC[];

[0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0,
 0,1,0,1, 0,1,0,1, 0,1,0,1, 0,0,0,0] @=> int hatC[];


// ═══════════════════════════════════════
// Arpeggio patterns (wide, cosmic sweeps)
// ═══════════════════════════════════════

["C3","Eb3","G3","C4", "Eb3","G3","C4","Eb4",
 "Ab3","C4","Eb4","Ab4","C4","Eb4","Ab4","C5",
 "G3","Bb3","D4","G4", "Bb3","D4","G4","Bb4",
 "F3","Ab3","C4","F4", "Ab3","C4","F4","Ab4"] @=> string arpA[];


// ═══════════════════════════════════════
// Play functions
// ═══════════════════════════════════════

fun void playMel(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => melody.freq;
    melEnv.keyOn();
    d - 5::ms => now;
    melEnv.keyOff();
    5::ms => now;
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
// Main loop: Deep Space → Asteroids → Boss → Asteroids
// ═══════════════════════════════════════

<<< "Space Quest started |", bpm, "BPM |", masterVol, "vol" >>>;

while (true) {
    playSection(melA, basA, arpA, drumA, hatA, 2);
    playSection(melB, basB, arpA, drumB, hatB, 2);
    playSection(melC, basC, arpA, drumC, hatC, 2);
    playSection(melB, basB, arpA, drumB, hatB, 1);
}
