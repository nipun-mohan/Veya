import UIKit

/// Veya's system-wide keyboard. The keyboard owns the interaction surface and
/// text insertion. The containing Veya app owns microphone and speech access.
final class KeyboardViewController: UIInputViewController {
  private let defaults = UserDefaults(suiteName: "group.app.veya.veya")!
  private var poller: Timer?
  private var elapsedTimer: Timer?
  private var elapsedSeconds = 0
  private var selectedStyle = "Neutral"

  private let ink = UIColor(red: 0.106, green: 0.027, blue: 0.204, alpha: 1)
  private let teal = UIColor(red: 0.188, green: 0.063, blue: 0.353, alpha: 1)
  private let paper = UIColor(red: 1, green: 0.980, blue: 0.953, alpha: 1)
  private let line = UIColor(red: 0.914, green: 0.890, blue: 0.910, alpha: 1)
  private let mango = UIColor(red: 1, green: 0.616, blue: 0.106, alpha: 1)
  private let orange = UIColor(red: 1, green: 0.392, blue: 0.165, alpha: 1)

  private let idlePanel = UIView()
  private let recordingPanel = UIView()
  private let styleButton = UIButton(type: .system)
  private let dictateButton = UIButton(type: .system)
  private let finishButton = UIButton(type: .system)
  private let timerLabel = UILabel()
  private let waveform = UIStackView()
  private let styleMenu = UIStackView()
  private let keyRows = UIStackView()
  private let handoffNotice = UILabel()
  private var keyboardHeightConstraint: NSLayoutConstraint?
  private var waveformBars: [UIView] = []

  override func loadView() {
    // UIInputViewController's default root view can be allocated at zero height
    // by the host. Give the extension a concrete input view before its child
    // views and constraints are created.
    view = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 330), inputViewStyle: .keyboard)
  }

  override func updateViewConstraints() {
    super.updateViewConstraints()
    guard keyboardHeightConstraint == nil else { return }
    let constraint = NSLayoutConstraint(
      item: view!, attribute: .height, relatedBy: .equal,
      toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 330
    )
    constraint.priority = .required
    view.addConstraint(constraint)
    keyboardHeightConstraint = constraint
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    selectedStyle = defaults.string(forKey: "veya_keyboard_style") ?? "Neutral"
    setupInterface()
    poller = Timer.scheduledTimer(timeInterval: 0.30, target: self, selector: #selector(refreshState), userInfo: nil, repeats: true)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    poller?.invalidate()
    elapsedTimer?.invalidate()
  }

  private func setupInterface() {
    view.backgroundColor = paper
    // A keyboard extension has no intrinsic height; updateViewConstraints pins
    // it to its intended full keyboard size.
    preferredContentSize = CGSize(width: 0, height: 330)
    configureIdlePanel()
    configureRecordingPanel()
    configureStyleMenu()
    view.addSubview(idlePanel)
    view.addSubview(recordingPanel)
    view.addSubview(styleMenu)
    [idlePanel, recordingPanel].forEach { panel in
      NSLayoutConstraint.activate([
        panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        panel.topAnchor.constraint(equalTo: view.topAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }
    NSLayoutConstraint.activate([
      styleMenu.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      styleMenu.bottomAnchor.constraint(equalTo: styleButton.topAnchor, constant: -8),
      styleMenu.widthAnchor.constraint(equalToConstant: 176),
    ])
    recordingPanel.isHidden = true
    styleMenu.isHidden = true
  }

  private func configureIdlePanel() {
    idlePanel.translatesAutoresizingMaskIntoConstraints = false
    let bar = UIStackView()
    bar.axis = .horizontal; bar.alignment = .center; bar.spacing = 10; bar.translatesAutoresizingMaskIntoConstraints = false
    let brand = UILabel()
    brand.text = "veya"; brand.textColor = ink; brand.font = .systemFont(ofSize: 17, weight: .heavy)
    styleButton.configuration = pillConfiguration(title: selectedStyle, foreground: ink, background: .white)
    styleButton.addTarget(self, action: #selector(toggleStyleMenu), for: .touchUpInside)
    dictateButton.configuration = pillConfiguration(title: "", foreground: .white, background: teal, image: "mic.fill")
    dictateButton.addTarget(self, action: #selector(startDictation), for: .touchUpInside)
    bar.addArrangedSubview(brand); bar.addArrangedSubview(UIView()); bar.addArrangedSubview(styleButton); bar.addArrangedSubview(dictateButton)
    idlePanel.addSubview(bar)
    handoffNotice.text = ""
    handoffNotice.textColor = UIColor(red: 0.33, green: 0.28, blue: 0.40, alpha: 1)
    handoffNotice.font = .systemFont(ofSize: 12, weight: .semibold)
    handoffNotice.textAlignment = .center
    handoffNotice.numberOfLines = 1
    handoffNotice.translatesAutoresizingMaskIntoConstraints = false
    idlePanel.addSubview(handoffNotice)
    keyRows.axis = .vertical; keyRows.spacing = 7; keyRows.distribution = .fillEqually; keyRows.translatesAutoresizingMaskIntoConstraints = false
    ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"].forEach { letters in
      let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 5
      letters.map(String.init).forEach { row.addArrangedSubview(keyButton($0)) }
      keyRows.addArrangedSubview(row)
    }
    let actions = UIStackView(); actions.axis = .horizontal; actions.distribution = .fill; actions.spacing = 6
    let number = keyButton("123")
    let globe = UIButton(type: .system); globe.setImage(UIImage(systemName: "globe"), for: .normal); globe.tintColor = ink; globe.addTarget(self, action: #selector(advanceKeyboard), for: .touchUpInside)
    let space = keyButton("space")
    let delete = UIButton(type: .system); delete.setImage(UIImage(systemName: "delete.left"), for: .normal); delete.tintColor = ink; delete.backgroundColor = .white; delete.layer.cornerRadius = 8; delete.addTarget(self, action: #selector(deleteCharacter), for: .touchUpInside)
    [number, globe, space, delete].forEach { actions.addArrangedSubview($0) }
    number.widthAnchor.constraint(equalToConstant: 48).isActive = true; globe.widthAnchor.constraint(equalToConstant: 48).isActive = true; delete.widthAnchor.constraint(equalToConstant: 48).isActive = true
    keyRows.addArrangedSubview(actions); idlePanel.addSubview(keyRows)
    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: idlePanel.topAnchor, constant: 10), bar.leadingAnchor.constraint(equalTo: idlePanel.leadingAnchor, constant: 16), bar.trailingAnchor.constraint(equalTo: idlePanel.trailingAnchor, constant: -16),
      dictateButton.widthAnchor.constraint(equalToConstant: 54), dictateButton.heightAnchor.constraint(equalToConstant: 42), styleButton.heightAnchor.constraint(equalToConstant: 42),
      handoffNotice.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 5), handoffNotice.leadingAnchor.constraint(equalTo: idlePanel.leadingAnchor, constant: 12), handoffNotice.trailingAnchor.constraint(equalTo: idlePanel.trailingAnchor, constant: -12), handoffNotice.heightAnchor.constraint(equalToConstant: 16),
      keyRows.topAnchor.constraint(equalTo: handoffNotice.bottomAnchor, constant: 5), keyRows.leadingAnchor.constraint(equalTo: idlePanel.leadingAnchor, constant: 8), keyRows.trailingAnchor.constraint(equalTo: idlePanel.trailingAnchor, constant: -8), keyRows.bottomAnchor.constraint(equalTo: idlePanel.bottomAnchor, constant: -9),
    ])
  }

  private func configureRecordingPanel() {
    recordingPanel.translatesAutoresizingMaskIntoConstraints = false; recordingPanel.backgroundColor = teal
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark"), for: .normal); close.tintColor = .white; close.backgroundColor = UIColor.white.withAlphaComponent(0.14); close.layer.cornerRadius = 21; close.addTarget(self, action: #selector(cancelDictation), for: .touchUpInside); close.translatesAutoresizingMaskIntoConstraints = false
    let recordStyle = UIButton(type: .system)
    recordStyle.configuration = pillConfiguration(title: selectedStyle, foreground: .white, background: UIColor.white.withAlphaComponent(0.14)); recordStyle.addTarget(self, action: #selector(toggleStyleMenu), for: .touchUpInside); recordStyle.translatesAutoresizingMaskIntoConstraints = false
    recordStyle.tag = 765
    finishButton.configuration = pillConfiguration(title: "End", foreground: .white, background: orange, image: "stop.fill"); finishButton.addTarget(self, action: #selector(stopDictation), for: .touchUpInside); finishButton.translatesAutoresizingMaskIntoConstraints = false
    let listening = UILabel(); listening.text = "Listening…"; listening.textColor = .white; listening.font = .systemFont(ofSize: 19, weight: .bold); listening.translatesAutoresizingMaskIntoConstraints = false
    timerLabel.text = "00:00"; timerLabel.textColor = UIColor.white.withAlphaComponent(0.80); timerLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold); timerLabel.translatesAutoresizingMaskIntoConstraints = false
    waveform.axis = .horizontal; waveform.alignment = .center; waveform.distribution = .fillEqually; waveform.spacing = 6; waveform.translatesAutoresizingMaskIntoConstraints = false
    for height in [20, 35, 52, 70, 82, 70, 52, 35, 20] {
      let bar = UIView(); bar.backgroundColor = mango; bar.layer.cornerRadius = 4; bar.heightAnchor.constraint(equalToConstant: CGFloat(height)).isActive = true; waveform.addArrangedSubview(bar); waveformBars.append(bar)
    }
    [close, recordStyle, finishButton, waveform, listening, timerLabel].forEach { recordingPanel.addSubview($0) }
    NSLayoutConstraint.activate([
      close.leadingAnchor.constraint(equalTo: recordingPanel.leadingAnchor, constant: 18), close.topAnchor.constraint(equalTo: recordingPanel.topAnchor, constant: 16), close.widthAnchor.constraint(equalToConstant: 42), close.heightAnchor.constraint(equalToConstant: 42),
      recordStyle.centerXAnchor.constraint(equalTo: recordingPanel.centerXAnchor), recordStyle.centerYAnchor.constraint(equalTo: close.centerYAnchor), recordStyle.heightAnchor.constraint(equalToConstant: 42),
      finishButton.trailingAnchor.constraint(equalTo: recordingPanel.trailingAnchor, constant: -18), finishButton.centerYAnchor.constraint(equalTo: close.centerYAnchor), finishButton.heightAnchor.constraint(equalToConstant: 42),
      waveform.centerXAnchor.constraint(equalTo: recordingPanel.centerXAnchor), waveform.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 22), waveform.widthAnchor.constraint(equalToConstant: 205), waveform.heightAnchor.constraint(equalToConstant: 92),
      listening.topAnchor.constraint(equalTo: waveform.bottomAnchor, constant: 10), listening.centerXAnchor.constraint(equalTo: recordingPanel.centerXAnchor),
      timerLabel.topAnchor.constraint(equalTo: listening.bottomAnchor, constant: 8), timerLabel.centerXAnchor.constraint(equalTo: recordingPanel.centerXAnchor),
    ])
  }

  private func configureStyleMenu() {
    styleMenu.axis = .vertical; styleMenu.spacing = 0; styleMenu.backgroundColor = .white; styleMenu.layer.cornerRadius = 16; styleMenu.layer.shadowColor = UIColor.black.cgColor; styleMenu.layer.shadowOpacity = 0.16; styleMenu.layer.shadowRadius = 12; styleMenu.layer.shadowOffset = CGSize(width: 0, height: 5); styleMenu.translatesAutoresizingMaskIntoConstraints = false
    ["Neutral", "Casual", "Formal", "Hindi", "Malayalam"].forEach { title in
      let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.setTitleColor(ink, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold); button.contentHorizontalAlignment = .left; button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20); button.heightAnchor.constraint(equalToConstant: 44).isActive = true; button.addTarget(self, action: #selector(selectStyle(_:)), for: .touchUpInside); styleMenu.addArrangedSubview(button)
    }
  }

  private func keyButton(_ title: String) -> UIButton {
    let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.setTitleColor(ink, for: .normal); button.titleLabel?.font = .systemFont(ofSize: title == "space" ? 15 : 18, weight: .medium); button.backgroundColor = .white; button.layer.borderColor = line.cgColor; button.layer.borderWidth = 1; button.layer.cornerRadius = 8; button.heightAnchor.constraint(equalToConstant: 42).isActive = true; button.addTarget(self, action: #selector(typeKey(_:)), for: .touchUpInside); return button
  }

  private func pillConfiguration(title: String, foreground: UIColor, background: UIColor, image: String? = nil) -> UIButton.Configuration {
    var config = UIButton.Configuration.filled(); config.title = title; config.image = image.flatMap(UIImage.init(systemName:)); config.imagePadding = title.isEmpty ? 0 : 7; config.baseForegroundColor = foreground; config.baseBackgroundColor = background; config.cornerStyle = .capsule; config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14); return config
  }

  @objc private func startDictation() {
    defaults.removeObject(forKey: "veya_keyboard_text")
    defaults.removeObject(forKey: "veya_keyboard_command")
    defaults.set(selectedStyle, forKey: "veya_keyboard_style")
    defaults.set("launching", forKey: "veya_keyboard_state")
    handoffNotice.text = "Opening Veya…"
    extensionContext?.open(URL(string: "veya://dictate")!) { [weak self] opened in
      DispatchQueue.main.async {
        guard let self else { return }
        self.handoffNotice.text = opened
          ? "Veya activated — swipe back when recording starts"
          : "Open Veya to record, then swipe back to insert"
      }
    }
  }
  @objc private func stopDictation() { defaults.set("stop", forKey: "veya_keyboard_command"); finishButton.isEnabled = false }
  @objc private func cancelDictation() { defaults.set("cancel", forKey: "veya_keyboard_command"); showRecording(false) }
  @objc private func toggleStyleMenu() { styleMenu.isHidden.toggle() }
  @objc private func selectStyle(_ sender: UIButton) {
    guard let title = sender.title(for: .normal) else { return }
    selectedStyle = title; defaults.set(title, forKey: "veya_keyboard_style"); styleButton.configuration = pillConfiguration(title: title, foreground: ink, background: .white)
    (view.viewWithTag(765) as? UIButton)?.configuration = pillConfiguration(title: title, foreground: .white, background: UIColor.white.withAlphaComponent(0.14))
    styleMenu.isHidden = true
  }
  @objc private func typeKey(_ sender: UIButton) { guard let value = sender.title(for: .normal) else { return }; textDocumentProxy.insertText(value == "space" ? " " : value.lowercased()) }
  @objc private func deleteCharacter() { textDocumentProxy.deleteBackward() }
  @objc private func advanceKeyboard() { advanceToNextInputMode() }

  @objc private func refreshState() {
    switch defaults.string(forKey: "veya_keyboard_state") ?? "idle" {
    case "recording": showRecording(true)
    case "processing": showRecording(true); finishButton.isEnabled = false
    case "ready":
      if let text = defaults.string(forKey: "veya_keyboard_text"), !text.isEmpty { textDocumentProxy.insertText(text) }
      defaults.removeObject(forKey: "veya_keyboard_text"); defaults.set("idle", forKey: "veya_keyboard_state"); showRecording(false)
    case "failed": showRecording(false)
    default: break
    }
  }

  private func showRecording(_ visible: Bool) {
    guard recordingPanel.isHidden == visible else { return }
    recordingPanel.isHidden = !visible; idlePanel.isHidden = visible; styleMenu.isHidden = true
    if !visible { handoffNotice.text = "" }
    if visible {
      elapsedSeconds = 0; timerLabel.text = "00:00"; finishButton.isEnabled = true; animateWaveform(); elapsedTimer?.invalidate()
      elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in guard let self else { return }; self.elapsedSeconds += 1; self.timerLabel.text = String(format: "%02d:%02d", self.elapsedSeconds / 60, self.elapsedSeconds % 60) }
    } else {
      elapsedTimer?.invalidate(); waveformBars.forEach { $0.layer.removeAllAnimations(); $0.transform = .identity }
    }
  }

  private func animateWaveform() {
    waveformBars.enumerated().forEach { index, bar in
      UIView.animate(withDuration: 0.42 + Double(index % 3) * 0.12, delay: Double(index) * 0.045, options: [.autoreverse, .repeat, .allowUserInteraction, .curveEaseInOut]) { bar.transform = CGAffineTransform(scaleX: 1, y: index.isMultiple(of: 2) ? 1.15 : 0.62) }
    }
  }
}
