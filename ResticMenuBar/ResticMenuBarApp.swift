//
//  ResticMenuBarApp.swift
//  ResticMenuBar
//
//  Created by Stephen Lynn on 12/13/24.
//

import SwiftUI
import Foundation
import Puppy

var APP_NAME = "ResticMenuBar"

var STATUS_IDLE = "Idle"
var STATUS_RUNNING: String = "Running..."
var IMAGE_IDLE: String = "umbrella"
var IMAGE_RUNNING: String = "umbrella.fill"

// Puppy log config
struct LogFormatter: LogFormattable {
    private let dateFormat = DateFormatter()
    
    init(){
        dateFormat.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    }
    
    func formatMessage(_ level: LogLevel, message: String, tag: String, function: String, file: String, line: UInt, swiftLogInfo: [String : String], label: String, date: Date, threadID: UInt64) -> String {
        let date = dateFormatter(date, withFormatter: dateFormat)
        return "\(date) [\(level)] \(message)".colorize(level.color)
    }
}


@main
struct ResticMenuBarApp: App {
    
    enum RunState {
        case idle, running, alert, setup
    }
    
    let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(APP_NAME)
    let runScript = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(APP_NAME).appendingPathComponent("run.sh")
    let tailScript = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(APP_NAME).appendingPathComponent("tail.sh")
    
    var log = Puppy(loggers: [try! FileRotationLogger("net.quikstorm.ResticMenuBar.filerotation",
                                                      logFormat: LogFormatter(),
                                   fileURL: URL(fileURLWithPath: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(APP_NAME).appendingPathComponent("log.txt").path(percentEncoded: false)).absoluteURL,
                                   rotationConfig: RotationConfig(suffixExtension: .date_uuid, maxFileSize: 10 * 1024 * 1024, maxArchivedFilesCount: 3))])

    var idleIcon : Image = Image(nsImage: {
        let ratio = $0.size.height / $0.size.width
        $0.size.height = 18
        $0.size.width = 18 / ratio
        return $0
    } (NSImage(named: "Umbrella Template")!))
    
    var runningIcon : Image = Image(nsImage: {
        let ratio = $0.size.height / $0.size.width
        $0.size.height = 18
        $0.size.width = 18 / ratio
        return $0
    } (NSImage(named: "Umbrella Running Template")!))
    
    var alertIcon : Image = Image(nsImage: {
        let ratio = $0.size.height / $0.size.width
        $0.size.height = 18
        $0.size.width = 18 / ratio
        return $0
    } (NSImage(named: "Umbrella Alert Template")!))
    
    let timer = DispatchSource.makeTimerSource(queue:DispatchQueue.global(qos:.background))

    @State var initialized: Bool = false
    @State var runState: RunState = RunState.idle
    @State var backupStartTime: String = "None"
    @AppStorage("net.quikstorm.ResticMenuBar.lastBackup") var lastBackup: String = "None"
    
    // triggered by launch detection in the view
    func firstRun(){
        do{
            // create the support directory
            if !FileManager.default.fileExists(atPath: appSupportDir.path) {
                try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            }
            
            // create the run script
            if !FileManager.default.fileExists(atPath: runScript.path){
                runState = .setup
            }
            
        } catch {
            log.error(error.localizedDescription)
        }
    }
    
    
    func getNowString() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    
    func runBackup() {
        
        do {
            
            log.debug("runBackup")
            
            if ( runState != RunState.running ){
                
                if !FileManager.default.fileExists(atPath: runScript.path){
                    runState = RunState.setup
                    return
                }
                
                if !FileManager.default.isExecutableFile(atPath: runScript.path){
                    log.error("\(runScript.path) is not executable.  Please make sure it has executable permissions (e.g. chmod +x run.sh)")
                    runState = RunState.setup
                    return
                }
                
                DispatchQueue.main.async {
                    log.debug("change icon")
                    runState = RunState.running
                    backupStartTime = getNowString()
                }
                
                let process = Process()
                let pipe = Pipe()
                process.arguments = []
                process.launchPath = appSupportDir.appendingPathComponent("run.sh").path(percentEncoded: false)
                process.currentDirectoryURL = appSupportDir;
                process.standardInput = nil
                process.standardError = process.standardOutput
                process.standardOutput = pipe
                
                log.info("Starting Backup")
                
                var buffer = Data()
                let delimiter = "\n".data(using: .utf8)!
                
                pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    if !data.isEmpty {
                        buffer.append(data)
                        
                        while let range = buffer.range(of: delimiter) {
                            let line = buffer.subdata(in:0..<range.lowerBound)
                            if let lineString = String(data: line, encoding: .utf8) {
                                log.verbose(lineString)
                            }
                            buffer.removeSubrange(0..<range.upperBound)
                        }
                    }
                }
                
                try process.run()
                log.debug("process start")
                process.waitUntilExit()
                log.debug("process exit")
                
                pipe.fileHandleForReading.readabilityHandler = nil
                
                if !buffer.isEmpty, let lineString = String(data: buffer, encoding: .utf8) {
                    print("run.sh: \(lineString)")
                }
                
                
                if ( process.terminationStatus == 0 ){
                    log.info("Backup Complete")
                    
                    DispatchQueue.main.async {
                        lastBackup = getNowString()
                        runState = RunState.idle
                    }
                    
                } else {
                    log.info("Backup failed exitCode: \(process.terminationStatus)")
                    
                    DispatchQueue.main.async {
                        runState = RunState.alert
                    }
                }
                
            } else {
                log.info("Backup already running")
            }
        } catch {
            log.error(error.localizedDescription)
        }

    }
    
    func startTimer(){
        timer.schedule(deadline: .now() + 5, repeating: 3600) // run the first time in 5 seconds, then run every hour after that
        timer.setEventHandler {
            DispatchQueue.global().async(execute: runBackup)
        }
        timer.resume()
        log.debug("started timer")
    }
    
    func getStatusText() -> String {
        switch(runState){
            case .idle: return "Idle"
            case .running: return "Backup started at \(backupStartTime)"
            case .alert: return "Failed at \(backupStartTime) - see log"
            case .setup: return "Setup run.sh in Support Folder"
        }
    }
    
    func tailLog() {
        // this will prompt that it wants to open terminal, but it's alot easier that implemetning a full view window
        // and re-implementing or piping 'tail'
        do {
            let tailProcess = Process()
            tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            tailProcess.arguments = ["-e", "tell app \"Terminal\" to do script \"trap exit INT; tail -n500 -f \\\"$HOME/Library/Application Support/ResticMenuBar/log.txt\\\"; exit\""]
            tailProcess.standardOutput = nil
            try tailProcess.run()
        } catch {
            log.error("Error launching log tail \(error.localizedDescription)")
        }
    }
     
    // need a reference to the scenePhase so we can watch for it to change to detect app launch
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
    
        MenuBarExtra {
            Text (
                getStatusText()
            )
            Divider()
            Text("Last Backup: \(lastBackup)")
            Divider()
            Button("Backup Now"){
                DispatchQueue.global().async(execute: runBackup)
            }.disabled(runState == RunState.running)
            Divider()
            Button("Open Support Folder"){
                NSWorkspace.shared.open(appSupportDir)
            }
            Button("View Log"){
                tailLog()
            }
            Divider()
            Button("Quit"){
                log.info("Quit at \(getNowString())")
                exit(0)
            }
        }
        label: {
            switch(runState) {
                case .idle:
                    return idleIcon
                case .running:
                    return runningIcon
                case .alert:
                    return alertIcon
                case .setup:
                    return alertIcon
            }
        }
        
        // awkward way we have to run on start, within the view context so that the view can be updated
        .onChange(of: scenePhase, initial: true ){
            
            if ( !initialized ){
                initialized = true
                log.info("ResticMenuBarApp started at \(getNowString())")
                firstRun()
                startTimer()
            }
        }
            
    }
}


/* unused bits
 
 //    func showFirstRunWindow(){
 //        let firstLaunchWindow = NSWindow(
 //            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
 //            styleMask: [.titled, .closable],
 //            backing: .buffered, defer: false)
 //        let contentView = NSHostingView(rootView: FirstLaunchView())
 //        firstLaunchWindow.title = "Restic Menu Bar - First Run"
 //        firstLaunchWindow.contentView = contentView
 //        firstLaunchWindow.center()
 //        firstLaunchWindow.makeKeyAndOrderFront(nil)
 //    }
 
 //                // create the runScript file
 //                FileManager.default.createFile(atPath: runScript.path, contents: "#!/bin/sh\n\n# implement script here\n\n#the working directory when invoked will be this directory\n\n#restic backup ...\n\necho 'run script not implemented'\n\n".data(using: .utf8))
 //
 //                // make the run script executable
 //                let setExecutableProcess = Process()
 //                setExecutableProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
 //                setExecutableProcess.arguments = ["+x", runScript.path(percentEncoded: false)]
 //                try setExecutableProcess.run()
 //                setExecutableProcess.waitUntilExit()
                 
                 //showFirstRunWindow()
 
 //        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
 //            NSLog("timer")
 //            DispatchQueue.global().async(execute: runBackup)
 //        }
 
 
 //MenuBarExtra("ResticMeuBar", systemImage: running ? "umbrella.fill" : "umbrella" ){
 
 
 struct FirstLaunchView: View {
     var body: some View {
         VStack {
             Text("Please configure the run.sh script in the application support folder.")
             Button("Open Support Folder"){
                 NSWorkspace.shared.open(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(APP_NAME))
             }
         }
         .padding()
     }
 }
 
 */
