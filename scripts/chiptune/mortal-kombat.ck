// Solo Factory — Mortal Kombat-style Fighter Theme
// Aggressive Em/Am riffs, heavy drums, dark energy
// Run: chuck mortal-kombat.ck or chuck mortal-kombat.ck:0.1

0.15 => float masterVol;
if (me.args() > 0) Std.atof(me.arg(0)) => masterVol;

150 => float bpm;
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
    if (n == "F3") return 174.61;
    if (n == "F#3") return 185.00;
    if (n == "G3") return 196.00;
    if (n == "A3") return 220.00;
    if (n == "Bb3") return 233.08;
    if (n == "B3") return 246.94;
    if (n == "C4") return 261.63;
    if (n == "D4") return 293.66;
    if (n == "Eb4") return 311.13;
    if (n == "E4") return 329.63;
    if (n == "F4") return 349.23;
    if (n == "F#4") return 369.99;
    if (n == "G4") return 392.00;
    if (n == "A4") return 440.00;
    if (n == "Bb4") return 466.16;
    if (n == "B4") return 493.88;
    if (n == "C5") return 523.25;
    if (n == "D5") return 587.33;
    if (n == "E5") return 659.25;
    return 0.0;
}

// ── Channels (heavier sound) ──
SqrOsc melody => ADSR melEnv => Gain melGain => dac;
melEnv.set(2::ms, 60::ms, 0.7, 50::ms);
masterVol * 0.5 => melGain.gain;

PulseOsc bass => ADSR basEnv => Gain basGain => dac;
0.5 => bass.width;
basEnv.set(2::ms, 40::ms, 0.8, 30::ms);
masterVol * 0.4 => basGain.gain;

SawOsc lead => ADSR leadEnv => Gain leadGain => dac;
leadEnv.set(3::ms, 50::ms, 0.5, 60::ms);
masterVol * 0.2 => leadGain.gain;

Noise noiz => ADSR drumEnv => HPF drumHpf => Gain drumGain => dac;
drumEnv.set(1::ms, 25::ms, 0.0, 8::ms);
drumHpf.freq(600);
masterVol * 0.25 => drumGain.gain;

Noise hihat => ADSR hatEnv => HPF hatHpf => Gain hatGain => dac;
hatEnv.set(1::ms, 10::ms, 0.0, 5::ms);
hatHpf.freq(3500);
masterVol * 0.12 => hatGain.gain;


// ═══════════════════════════════════════
// SECTION A: Main Riff (aggressive Em power chords)
// ═══════════════════════════════════════

["E4","E4","E4","_", "E4","E4","Eb4","E4",
 "_","E4","E4","_",  "G4","F#4","E4","_",
 "E4","E4","E4","_", "E4","E4","Eb4","E4",
 "_","A4","G4","E4", "D4","E4","_","_"] @=> string melA[];

["E2","_","E2","E2", "_","E2","_","E2",
 "E2","_","E2","E2", "_","E2","_","E2",
 "A2","_","A2","A2", "_","A2","_","A2",
 "B2","_","B2","B2", "_","E2","_","E2"] @=> string basA[];

[1,0,1,0, 1,0,1,1, 0,1,0,1, 0,1,0,0,
 1,0,1,0, 1,0,1,1, 0,1,0,1, 1,0,1,0] @=> int drumA[];

[0,1,0,1, 0,1,0,0, 1,0,1,0, 1,0,1,1,
 0,1,0,1, 0,1,0,0, 1,0,1,0, 0,1,0,1] @=> int hatA[];


// ═══════════════════════════════════════
// SECTION B: Fight Sequence (chromatic aggression)
// ═══════════════════════════════════════

["A4","_","C5","B4", "A4","G4","E4","_",
 "A4","B4","C5","D5", "E5","D5","C5","B4",
 "A4","_","A4","G4", "F#4","E4","D4","_",
 "E4","F#4","G4","A4", "B4","A4","G4","E4"] @=> string melB[];

["A2","_","A2","_", "A2","_","A2","_",
 "C3","_","C3","_", "D3","_","D3","_",
 "A2","_","A2","_", "G3","_","G3","_",
 "E2","_","E2","_", "E2","_","E2","_"] @=> string basB[];

[1,1,0,1, 0,1,1,0, 1,1,0,1, 0,1,1,0,
 1,1,0,1, 0,1,1,0, 1,0,1,1, 1,1,0,1] @=> int drumB[];

[0,0,1,0, 1,0,0,1, 0,0,1,0, 1,0,0,1,
 0,0,1,0, 1,0,0,1, 0,1,0,0, 0,0,1,0] @=> int hatB[];


// ═══════════════════════════════════════
// SECTION C: Fatality (dark, heavy, slow breakdown)
// ═══════════════════════════════════════

["E4","_","_","E4", "_","_","G4","F#4",
 "E4","_","_","E4", "D4","_","E4","_",
 "A4","_","_","A4", "_","_","C5","B4",
 "A4","G4","E4","_", "E4","_","E4","_"] @=> string melC[];

["E2","E2","_","_", "E2","E2","_","_",
 "E2","E2","_","_", "D3","D3","E2","_",
 "A2","A2","_","_", "A2","A2","_","_",
 "E2","_","E2","_", "E2","_","E2","_"] @=> string basC[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,0,1,
 1,0,0,1, 0,0,1,0, 1,0,0,0, 1,0,1,0] @=> int drumC[];

[0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,1,0,
 0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0] @=> int hatC[];


// ═══════════════════════════════════════
// Lead arpeggio patterns
// ═══════════════════════════════════════

["E3","G3","B3","E4", "G3","B3","E4","G4",
 "A3","C4","E4","A4", "C4","E4","A4","C5",
 "E3","G3","B3","E4", "G3","B3","E4","G4",
 "B3","E4","G4","B4", "E4","G4","B4","E5"] @=> string arpA[];


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

fun void playLead(string n, dur d) {
    if (n == "_") { d => now; return; }
    note(n) => lead.freq;
    leadEnv.keyOn();
    d - 3::ms => now;
    leadEnv.keyOff();
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
            spork ~ playLead(aNote, sixteenth);
            if (drums[dIdx] == 1) spork ~ kick(sixteenth);
            if (hats[hIdx] == 1) spork ~ hat(sixteenth);
            playMel(mel[i], sixteenth);
        }
    }
}

// ═══════════════════════════════════════
// Main loop: Riff → Fight → Fatality → repeat
// ═══════════════════════════════════════

<<< "Mortal Kombat started |", bpm, "BPM |", masterVol, "vol" >>>;

while (true) {
    playSection(melA, basA, arpA, drumA, hatA, 2);
    playSection(melB, basB, arpA, drumB, hatB, 2);
    playSection(melA, basA, arpA, drumA, hatA, 1);
    playSection(melC, basC, arpA, drumC, hatC, 2);
}
