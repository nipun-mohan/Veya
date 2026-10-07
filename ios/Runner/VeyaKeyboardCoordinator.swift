import AVFoundation
import Speech
import UIKit

/// Owns the microphone in the containing app and returns completed text to the
/// keyboard through the shared App Group. The keyboard never touches audio.
final class VeyaKeyboardCoordinator: NSObject {
  static let shared = VeyaKeyboardCoordinator()

  private let defaults = UserDefaults(suiteName: "group.app.veya.veya")!
  private var recognizer: SFSpeechRecognizer?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var presentation: UIViewController?
  private var commandPoller: Timer?
  private var maximumDurationTimer: Timer?
  private var lastTranscript = ""

  func start(from root: UIViewController?) {
    guard !engine.isRunning else { return }
    defaults.removeObject(forKey: "veya_keyboard_text")
    defaults.removeObject(forKey: "veya_keyboard_command")
    presentReturnHint(from: root)
    defaults.set("launching", forKey: "veya_keyboard_state")
    defaults.removeObject(forKey: "veya_keyboard_command")
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          self?.fail()
          return
        }
        self?.requestMicrophone()
      }
    }
  }

  /// The keyboard may not be permitted to launch its containing app directly.
  /// When the user opens Veya themselves, resume the pending handoff instead.
  func startPendingIfNeeded(from root: UIViewController?) {
    guard defaults.string(forKey: "veya_keyboard_state") == "launching" else { return }
    start(from: root)
  }

  private func requestMicrophone() {
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard granted else {
          self?.fail()
          return
        }
        self?.beginRecognition()
      }
    }
  }

  private func beginRecognition() {
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier()))
    guard let recognizer, recognizer.isAvailable else {
      fail()
      return
    }
    let audioRequest = SFSpeechAudioBufferRecognitionRequest()
    audioRequest.shouldReportPartialResults = true
    request = audioRequest
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let input = engine.inputNode
      let format = input.inputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        fail()
        return
      }
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
        audioRequest.append(buffer)
        guard let self else { return }
        let command = self.defaults.string(forKey: "veya_keyboard_command")
        if command == "stop" {
          self.defaults.removeObject(forKey: "veya_keyboard_command")
          DispatchQueue.main.async { self.finish(with: self.lastTranscript) }
        } else if command == "cancel" {
          self.defaults.removeObject(forKey: "veya_keyboard_command")
          DispatchQueue.main.async { self.cancel() }
        }
      }
      engine.prepare()
      try engine.start()
      defaults.set("recording", forKey: "veya_keyboard_state")
      maximumDurationTimer?.invalidate()
      maximumDurationTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
        guard let self else { return }
        self.finish(with: self.lastTranscript)
      }
      task = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
        if let result {
          self?.lastTranscript = result.bestTranscription.formattedString
          if result.isFinal {
            self?.finish(with: result.bestTranscription.formattedString)
          }
        } else if error != nil {
          self?.finish(with: self?.lastTranscript)
        }
      }
    } catch {
      fail()
    }
  }

  private func finish(with text: String?) {
    guard engine.isRunning || task != nil else { return }
    defaults.set("processing", forKey: "veya_keyboard_state")
    commandPoller?.invalidate()
    commandPoller = nil
    maximumDurationTimer?.invalidate()
    maximumDurationTimer = nil
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    lastTranscript = ""
    if let text, !text.isEmpty {
      defaults.set(applySelectedStyle(to: text), forKey: "veya_keyboard_text")
      defaults.set("ready", forKey: "veya_keyboard_state")
    } else {
      fail()
    }
    dismissReturnHint()
  }

  private func fail() {
    commandPoller?.invalidate()
    commandPoller = nil
    maximumDurationTimer?.invalidate()
    maximumDurationTimer = nil
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    defaults.set("failed", forKey: "veya_keyboard_state")
    dismissReturnHint()
  }

  private func cancel() {
    commandPoller?.invalidate()
    maximumDurationTimer?.invalidate()
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    defaults.set("idle", forKey: "veya_keyboard_state")
    dismissReturnHint()
  }

  /// Keep the selected mode with the keyboard handoff. Full language and tone
  /// rewrites are performed by Veya's authenticated processing service; this
  /// safe local fallback gives Formal output its expected message structure.
  private func applySelectedStyle(to text: String) -> String {
    guard defaults.string(forKey: "veya_keyboard_style") == "Formal" else {
      return text
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return trimmed }
    let sentence = first.uppercased() + trimmed.dropFirst()
    return sentence.hasSuffix(".") || sentence.hasSuffix("!") || sentence.hasSuffix("?")
      ? sentence : sentence + "."
  }

  private func localeIdentifier() -> String {
    switch defaults.string(forKey: "veya_keyboard_style") {
    case "Hindi": return "hi-IN"
    case "Malayalam": return "ml-IN"
    default: return "en-IN"
    }
  }

  private func presentReturnHint(from root: UIViewController?) {
    guard let root, presentation == nil else { return }
    let controller = UIViewController()
    controller.modalPresentationStyle = .fullScreen
    controller.view.backgroundColor = UIColor(red: 1, green: 0.980, blue: 0.953, alpha: 1)
    let icon = UIImageView(image: UIImage(systemName: "waveform.circle.fill"))
    icon.tintColor = UIColor(red: 1, green: 0.616, blue: 0.106, alpha: 1)
    icon.contentMode = .scaleAspectFit
    icon.translatesAutoresizingMaskIntoConstraints = false
    let badge = UILabel()
    badge.text = "● ACTIVE"
    badge.textColor = UIColor(red: 0.12, green: 0.54, blue: 0.33, alpha: 1)
    badge.font = .systemFont(ofSize: 13, weight: .bold)
    badge.textAlignment = .center
    badge.translatesAutoresizingMaskIntoConstraints = false
    let title = UILabel()
    title.text = "Veya activated"
    title.textColor = UIColor(red: 0.106, green: 0.027, blue: 0.204, alpha: 1)
    title.font = .systemFont(ofSize: 29, weight: .bold)
    title.textAlignment = .center
    title.translatesAutoresizingMaskIntoConstraints = false
    let body = UILabel()
    body.text = "Apple requires you to manually swipe back to start Veya."
    body.numberOfLines = 0
    body.textAlignment = .center
    body.textColor = UIColor(red: 0.40, green: 0.44, blue: 0.55, alpha: 1)
    body.font = .systemFont(ofSize: 17, weight: .regular)
    body.translatesAutoresizingMaskIntoConstraints = false
    let hint = UILabel()
    hint.text = "Swipe right to go back"
    hint.textColor = UIColor(red: 0.106, green: 0.027, blue: 0.204, alpha: 1)
    hint.font = .systemFont(ofSize: 17, weight: .semibold)
    hint.textAlignment = .center
    hint.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(icon)
    controller.view.addSubview(badge)
    controller.view.addSubview(title)
    controller.view.addSubview(body)
    controller.view.addSubview(hint)
    NSLayoutConstraint.activate([
      icon.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
      icon.bottomAnchor.constraint(equalTo: badge.topAnchor, constant: -20),
      icon.widthAnchor.constraint(equalToConstant: 64),
      icon.heightAnchor.constraint(equalToConstant: 64),
      badge.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
      badge.bottomAnchor.constraint(equalTo: title.topAnchor, constant: -28),
      badge.heightAnchor.constraint(equalToConstant: 44),
      title.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
      title.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor, constant: -28),
      body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
      body.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 36),
      body.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -36),
      hint.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
      hint.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -52),
    ])
    root.present(controller, animated: true)
    presentation = controller
  }

  private func dismissReturnHint() {
    DispatchQueue.main.async { [weak self] in
      self?.presentation?.dismiss(animated: true)
      self?.presentation = nil
    }
  }
}
