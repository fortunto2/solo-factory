// Solo Factory — 8-bit Pipeline Theme
// ChucK chiptune with multiple sections, varied melodies, proper musical structure
// Run: chuck solo-theme.ck
// Stop: chuck --kill or Ctrl-C

// ── Master volume (override via env or arg) ──
0.15 => float masterVol;

// ── BPM ──
140 => float bpm;
(60.0 / bpm)::second => dur beat;
beat / 4 => dur sixteenth;

// ── Note frequencies ──
fun float note(string n) {
    if (n == "_") return 0.0;
    // Octave 3
    if (n == "C3") return 130.81;
    if (n == "D3") return 146.83;
    if (n == "E3") return 164.81;
    if (n == "F3") return 174.61;
    if (n == "G3") return 196.00;
    if (n == "A3") return 220.00;
    if (n == "B3") return 246.94;
    // Octave 4
    if (n == "C4") return 261.63;
    if (n == "D4") return 293.66;
    if (n == "E4") return 329.63;
    if (n == "F4") return 349.23;
    if (n == "G4") return 392.00;
    if (n == "A4") return 440.00;
    if (n == "Bb4") return 466.16;
    if (n == "B4") return 493.88;
    // Octave 5
    if (n == "C5") return 523.25;
    if (n == "D5") return 587.33;
    if (n == "E5") return 659.25;
    if (n == "F5") return 698.46;
    if (n == "G5") return 783.99;
    if (n == "A5") return 880.00;
    return 0.0;
}

// ── Melody channel (square wave, duty cycle ~25%) ──
PulseOsc melody => ADSR melEnv => Gain melGain => dac;
0.25 => melody.width;
melEnv.set(5::ms, 50::ms, 0.6, 80::ms);
masterVol * 0.5 => melGain.gain;

// ── Bass channel (square wave, duty cycle ~50%) ──
PulseOsc bass => ADSR basEnv => Gain basGain => dac;
0.5 => bass.width;
basEnv.set(3::ms, 30::ms, 0.7, 50::ms);
masterVol * 0.35 => basGain.gain;

// ── Arpeggio channel (triangle-ish, narrow pulse) ──
PulseOsc arp => ADSR arpEnv => Gain arpGain => dac;
0.125 => arp.width;
arpEnv.set(2::ms, 40::ms, 0.4, 60::ms);
masterVol * 0.25 => arpGain.gain;

// ── Drums (noise) ──
Noise noiz => ADSR drumEnv => HPF drumHpf => Gain drumGain => dac;
drumEnv.set(1::ms, 20::ms, 0.0, 10::ms);
drumHpf.freq(800);
masterVol * 0.2 => drumGain.gain;

// Hi-hat
Noise hihat => ADSR hatEnv => HPF hatHpf => Gain hatGain => dac;
hatEnv.set(1::ms, 8::ms, 0.0, 5::ms);
hatHpf.freq(4000);
masterVol * 0.1 => hatGain.gain;


// ═══════════════════════════════════════
// SECTION A: Adventure Theme (C major, uplifting)
// ═══════════════════════════════════════

["C4","E4","G4","C5", "B4","G4","E4","D4",
 "E4","G4","A4","G4", "E4","C4","D4","_",
 "F4","A4","C5","A4", "G4","E4","D4","C4",
 "D4","F4","G4","A4", "G4","E4","C4","_"] @=> string melA[];

["C3","_","C3","_", "G3","_","G3","_",
 "A3","_","A3","_", "E3","_","E3","_",
 "F3","_","F3","_", "C3","_","C3","_",
 "G3","_","G3","_", "C3","_","G3","_"] @=> string basA[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0,
 1,0,0,1, 0,0,1,0, 1,0,1,0, 1,0,1,1] @=> int drumA[];

[0,0,1,0, 1,0,0,1, 0,0,1,0, 1,0,0,1,
 0,0,1,0, 1,0,0,1, 0,1,0,1, 0,1,0,0] @=> int hatA[];


// ═══════════════════════════════════════
// SECTION B: Determined March (Am, driving)
// ═══════════════════════════════════════

["A4","C5","E5","C5", "A4","G4","E4","_",
 "G4","B4","D5","B4", "G4","E4","D4","_",
 "F4","A4","C5","A4", "F4","E4","D4","C4",
 "E4","G4","A4","B4", "C5","B4","A4","_"] @=> string melB[];

["A3","_","A3","_", "E3","_","E3","_",
 "G3","_","G3","_", "D3","_","D3","_",
 "F3","_","F3","_", "C3","_","C3","_",
 "E3","_","E3","_", "A3","_","A3","_"] @=> string basB[];

[1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0,
 1,0,1,0, 1,0,1,0, 1,1,0,1, 1,0,0,1] @=> int drumB[];

[0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1,
 0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,1,0] @=> int hatB[];


// ═══════════════════════════════════════
// SECTION C: Victory Climb (G major, triumphant)
// ═══════════════════════════════════════

["G4","B4","D5","G5", "F5","D5","B4","A4",
 "G4","A4","B4","D5", "E5","D5","B4","G4",
 "C5","E5","G5","E5", "D5","B4","A4","G4",
 "A4","B4","D5","E5", "G5","_","G5","_"] @=> string melC[];

["G3","_","G3","_", "D3","_","D3","_",
 "G3","_","G3","_", "E3","_","E3","_",
 "C3","_","C3","_", "G3","_","G3","_",
 "D3","_","D3","_", "G3","_","G3","_"] @=> string basC[];

[1,0,0,1, 0,1,0,0, 1,0,0,1, 0,1,0,0,
 1,0,0,1, 0,1,0,0, 1,0,1,0, 1,1,1,1] @=> int drumC[];

[0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0,
 0,0,1,0, 0,0,1,0, 0,1,0,1, 0,0,0,0] @=> int hatC[];


// ═══════════════════════════════════════
// SECTION D: Korobeiniki-inspired (Em, Russian folk)
// ═══════════════════════════════════════

["E5","B4","C5","D5", "C5","B4","A4","_",
 "A4","C5","E5","D5", "C5","B4","_","_",
 "C5","E5","A5","G5", "F5","E5","D5","_",
 "D5","F5","E5","D5", "C5","B4","E4","_"] @=> string melD[];

["E3","_","E3","_", "A3","_","A3","_",
 "E3","_","E3","_", "B3","_","B3","_",
 "A3","_","A3","_", "G3","_","G3","_",
 "D3","_","D3","_", "E3","_","E3","_"] @=> string basD[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0,
 1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0] @=> int drumD[];

[0,0,1,0, 0,1,0,0, 0,0,1,0, 0,1,0,0,
 0,0,1,0, 0,1,0,0, 0,0,1,0, 0,1,0,0] @=> int hatD[];


// ═══════════════════════════════════════
// Arpeggio patterns (play between melody notes)
// ═══════════════════════════════════════

["C4","E4","G4","E4", "C4","G4","E4","G4",
 "A3","C4","E4","C4", "A3","E4","C4","E4",
 "F3","A3","C4","A3", "F3","C4","A3","C4",
 "G3","B3","D4","B3", "G3","D4","B3","D4"] @=> string arpA[];

["A3","C4","E4","C4", "A3","E4","C4","E4",
 "G3","B3","D4","B3", "G3","D4","B3","D4",
 "F3","A3","C4","A3", "F3","C4","A3","C4",
 "E3","G3","B3","G3", "E3","B3","G3","B3"] @=> string arpB[];


// ═══════════════════════════════════════
// Play functions
// ═══════════════════════════════════════

fun void playMelNote(string n, dur d) {
    if (n == "_") {
        d => now;
        return;
    }
    note(n) => melody.freq;
    melEnv.keyOn();
    d - 5::ms => now;
    melEnv.keyOff();
    5::ms => now;
}

fun void playBassNote(string n, dur d) {
    if (n == "_") {
        d => now;
        return;
    }
    note(n) => bass.freq;
    basEnv.keyOn();
    d - 3::ms => now;
    basEnv.keyOff();
    3::ms => now;
}

fun void playArpNote(string n, dur d) {
    if (n == "_") {
        d => now;
        return;
    }
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


// ═══════════════════════════════════════
// Section player — runs melody + bass + arp + drums concurrently
// ═══════════════════════════════════════

fun void playSection(string mel[], string bas[], string arps[],
                     int drums[], int hats[], int repeats) {
    for (0 => int rep; rep < repeats; rep++) {
        for (0 => int i; i < mel.size(); i++) {
            // Extract to temp vars (ChucK needs simple args for spork)
            bas[i % bas.size()] => string bNote;
            arps[i % arps.size()] => string aNote;
            i % drums.size() => int dIdx;
            i % hats.size() => int hIdx;
            // Sporked concurrent voices
            spork ~ playBassNote(bNote, sixteenth);
            spork ~ playArpNote(aNote, sixteenth);
            if (drums[dIdx] == 1) spork ~ kick(sixteenth);
            if (hats[hIdx] == 1) spork ~ hat(sixteenth);
            // Melody is synchronous (drives timing)
            playMelNote(mel[i], sixteenth);
        }
    }
}


// ═══════════════════════════════════════
// Main loop — cycles through sections forever
// Structure: A A B B C C D D (then repeat with variation)
// ═══════════════════════════════════════

<<< "Solo Chiptune started |", bpm, "BPM |", masterVol, "vol" >>>;

while (true) {
    // Cycle 1: A → B → C → D
    playSection(melA, basA, arpA, drumA, hatA, 2);
    playSection(melB, basB, arpB, drumB, hatB, 2);
    playSection(melC, basC, arpA, drumC, hatC, 2);
    playSection(melD, basD, arpB, drumD, hatD, 2);

    // Cycle 2: D → C → B → A (reverse for variety)
    playSection(melD, basD, arpB, drumD, hatD, 2);
    playSection(melC, basC, arpA, drumC, hatC, 2);
    playSection(melB, basB, arpB, drumB, hatB, 2);
    playSection(melA, basA, arpA, drumA, hatA, 2);
}
