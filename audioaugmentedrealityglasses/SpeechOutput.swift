import AVFoundation

// Declare a global instance of AVSpeechSynthesizer.
let speechSynthesizer = AVSpeechSynthesizer()

func speakText(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
    utterance.rate = 0.55

    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
    try? AVAudioSession.sharedInstance().setActive(true)

    if speechSynthesizer.isSpeaking {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    speechSynthesizer.speak(utterance)
}
