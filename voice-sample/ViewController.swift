//
//  ViewController.swift
//  voice-sample
//
//  Created by Shusaku Harada on 2019/03/06.
//  Copyright © 2019 Shusaku Harada. All rights reserved.
//

import UIKit
import Speech

class ViewController: UIViewController {

    @IBOutlet weak var buttonContainerView: UIView!
    @IBOutlet weak var voiceControlButton: UIButton!

    @IBOutlet weak var voiceTextView: UITextView!
    @IBOutlet weak var recognizingTextView: UITextView!
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        voiceTextView.isEditable = false
        recognizingTextView.isEditable = false
        recognizingTextView.text = ""
        
        voiceControlButton.setTitle("Start", for: .normal)
        voiceControlButton.addTarget(self, action: #selector(onVoiceControlButtonTapped(_:)), for: .touchUpInside)
        speechRecognizer.delegate = self

        requestRecognizerAuthorization()
    }

    private func requestRecognizerAuthorization() {
        // 認証処理
        SFSpeechRecognizer.requestAuthorization { authStatus in
            // メインスレッドで処理したい内容のため、OperationQueue.main.addOperationを使う
            OperationQueue.main.addOperation { [weak self] in
                self?.updateVoiceControlButton(authStatus)
            }
        }
    }
    
    private func updateVoiceControlButton(_ authStatus: SFSpeechRecognizerAuthorizationStatus) {
        let me = self
        switch authStatus {
        case .authorized:
            me.voiceControlButton.isEnabled = true
            me.voiceControlButton.setTitle("音声認識スタート", for: [])

        case .denied:
            me.voiceControlButton.isEnabled = false
            me.voiceControlButton.setTitle("音声認識へのアクセスが拒否されています。", for: .disabled)
            
        case .restricted:
            me.voiceControlButton.isEnabled = false
            me.voiceControlButton.setTitle("この端末で音声認識はできません。", for: .disabled)
            
        case .notDetermined:
            me.voiceControlButton.isEnabled = false
            me.voiceControlButton.setTitle("音声認識はまだ許可されていません。", for: .disabled)
        }
    }
    
    // Mark: -

    @objc private func onVoiceControlButtonTapped(_ sender: Any?) {
        if audioEngine.isRunning {
            print("Stopping...")
            audioEngine.stop()
            recognitionRequest?.endAudio()
            voiceControlButton.setTitle("停止中", for: [])
        } else {
            print("Starting...")
            try! startRecording()
            voiceControlButton.setTitle("音声認識を中止", for: [])
        }
    }

    private func startRecording() throws {
        refreshTask()
        
        let audioSession = AVAudioSession.sharedInstance()
        // 録音用のカテゴリをセット
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }
        
        // 録音が完了する前のリクエストを作るかどうかのフラグ。
        // trueだと現在-1回目のリクエスト結果が返ってくる模様。falseだとボタンをオフにしたときに音声認識の結果が返ってくる設定。
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let `self` = self else { return }
            
            var isFinal = false
            
            if let result = result {
                let segments = result.bestTranscription.segments.filter({$0.timestamp != 0})
                if segments.isEmpty {
                    self.recognizingTextView.text = result.bestTranscription.formattedString
                } else {
                    self.voiceTextView.text = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal

                print("---- >>>>")
                segments.enumerated().forEach({ (item) in
                    print("\(item.offset): \(item.element)")
                })
                print("---- <<<<\n")
            }
            
            // エラーがある、もしくは最後の認識結果だった場合の処理
            if error != nil || isFinal {
                if let error = error {
                    dump(error)
                }
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                self.voiceControlButton.isEnabled = true
                self.voiceControlButton.setTitle("音声認識スタート", for: [])
            }
        }
        
        // マイクから取得した音声バッファをリクエストに渡す
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        try startAudioEngine()
    }
    
    private func refreshTask() {
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
    }
    
    private func startAudioEngine() throws {
        // startの前にリソースを確保しておく。
        audioEngine.prepare()
        
        try audioEngine.start()
        
        voiceTextView.text = "どうぞ喋ってください。"
    }
}

extension ViewController: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            voiceControlButton.isEnabled = true
            voiceControlButton.setTitle("音声認識スタート", for: [])
        } else {
            voiceControlButton.isEnabled = false
            voiceControlButton.setTitle("音声認識ストップ", for: .disabled)
        }
    }
}
