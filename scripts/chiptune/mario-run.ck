// Solo Factory — Mario-style Platformer Theme
// Bouncy C major melodies, classic platformer energy
// Run: chuck mario-run.ck or chuck mario-run.ck:0.1

0.15 => float masterVol;
if (me.args() > 0) Std.atof(me.arg(0)) => masterVol;

160 => float bpm;
(60.0 / bpm)::second => dur beat;
beat / 4 => dur sixteenth;

// ── Note frequencies ──
fun float note(string n) {
    if (n == "_") return 0.0;
    if (n == "C3") return 130.81;
    if (n == "D3") return 146.83;
    if (n == "E3") return 164.81;
    if (n == "F3") return 174.61;
    if (n == "G3") return 196.00;
    if (n == "A3") return 220.00;
    if (n == "Bb3") return 233.08;
    if (n == "B3") return 246.94;
    if (n == "C4") return 261.63;
    if (n == "D4") return 293.66;
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
    if (n == "F5") return 698.46;
    if (n == "G5") return 783.99;
    if (n == "A5") return 880.00;
    return 0.0;
}

// ── Channels ──
PulseOsc melody => ADSR melEnv => Gain melGain => dac;
0.25 => melody.width;
melEnv.set(3::ms, 40::ms, 0.6, 60::ms);
masterVol * 0.5 => melGain.gain;

PulseOsc bass => ADSR basEnv => Gain basGain => dac;
0.5 => bass.width;
basEnv.set(3::ms, 25::ms, 0.7, 40::ms);
masterVol * 0.35 => basGain.gain;

PulseOsc arp => ADSR arpEnv => Gain arpGain => dac;
0.125 => arp.width;
arpEnv.set(2::ms, 30::ms, 0.4, 50::ms);
masterVol * 0.2 => arpGain.gain;

Noise noiz => ADSR drumEnv => HPF drumHpf => Gain drumGain => dac;
drumEnv.set(1::ms, 15::ms, 0.0, 8::ms);
drumHpf.freq(900);
masterVol * 0.18 => drumGain.gain;

Noise hihat => ADSR hatEnv => HPF hatHpf => Gain hatGain => dac;
hatEnv.set(1::ms, 6::ms, 0.0, 4::ms);
hatHpf.freq(5000);
masterVol * 0.08 => hatGain.gain;


// ═══════════════════════════════════════
// SECTION A: Overworld (bouncy, upbeat)
// ═══════════════════════════════════════

["E5","E5","_","E5", "_","C5","E5","_",
 "G5","_","_","_",   "G4","_","_","_",
 "C5","_","_","G4",  "_","_","E4","_",
 "_","A4","_","B4",  "_","Bb4","A4","_"] @=> string melA[];

["C3","_","C3","_", "G3","_","G3","_",
 "E3","_","E3","_", "C3","_","C3","_",
 "F3","_","F3","_", "C3","_","C3","_",
 "G3","_","G3","_", "C3","_","G3","_"] @=> string basA[];

[1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0,
 1,0,0,1, 0,0,1,0, 1,0,1,0, 1,0,0,1] @=> int drumA[];

[0,0,1,0, 1,0,0,1, 0,0,1,0, 0,1,0,0,
 0,0,1,0, 1,0,0,1, 0,1,0,1, 0,0,1,0] @=> int hatA[];


// ═══════════════════════════════════════
// SECTION B: Underground (mysterious, chromatic)
// ═══════════════════════════════════════

["C4","C5","A4","A4", "Bb4","_","Bb4","_",
 "C4","C5","A4","A4", "Bb4","_","Bb4","_",
 "F4","E4","D4","C4", "B3","A3","G3","_",
 "C4","E4","G4","C5", "B4","G4","E4","_"] @=> string melB[];

["C3","_","C3","_", "Bb3","_","Bb3","_",
 "C3","_","C3","_", "Bb3","_","Bb3","_",
 "F3","_","E3","_", "D3","_","C3","_",
 "C3","_","E3","_", "G3","_","C3","_"] @=> string basB[];

[1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0,
 1,0,0,0, 1,0,0,0, 1,0,1,0, 1,0,1,1] @=> int drumB[];

[0,0,0,1, 0,0,0,1, 0,0,0,1, 0,0,0,1,
 0,0,0,1, 0,0,0,1, 0,1,0,1, 0,0,0,0] @=> int hatB[];


// ═══════════════════════════════════════
// SECTION C: Star Power (fast, triumphant)
// ═══════════════════════════════════════

["C5","E5","G5","E5", "C5","E5","G5","A5",
 "G5","E5","C5","D5", "E5","C5","D5","_",
 "F5","A5","G5","F5", "E5","C5","D5","E5",
 "G5","F5","E5","D5", "C5","_","C5","_"] @=> string melC[];

["C3","E3","C3","E3", "C3","E3","C3","E3",
 "G3","B3","G3","B3", "G3","B3","G3","B3",
 "F3","A3","F3","A3", "F3","A3","F3","A3",
 "G3","B3","G3","B3", "C3","_","C3","_"] @=> string basC[];

[1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0,
 1,0,1,0, 1,0,1,0, 1,1,0,1, 1,1,1,1] @=> int drumC[];

[0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1,
 0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1] @=> int hatC[];


// ═══════════════════════════════════════
// Arpeggio patterns
// ═══════════════════════════════════════

["C4","E4","G4","E4", "C4","G4","E4","G4",
 "G3","B3","D4","B3", "G3","D4","B3","D4",
 "F3","A3","C4","A3", "F3","C4","A3","C4",
 "G3","B3","D4","B3", "G3","D4","B3","D4"] @=> string arpA[];


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
// Main loop: Overworld → Underground → Star Power
// ═══════════════════════════════════════

<<< "Mario Run started |", bpm, "BPM |", masterVol, "vol" >>>;

while (true) {
    playSection(melA, basA, arpA, drumA, hatA, 2);
    playSection(melB, basB, arpA, drumB, hatB, 2);
    playSection(melC, basC, arpA, drumC, hatC, 2);
    playSection(melA, basA, arpA, drumA, hatA, 1);
}
