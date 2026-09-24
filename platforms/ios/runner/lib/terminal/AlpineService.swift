import AcodeAlpine
import Foundation

final class AlpineService: BaseService {
    private let runtime = AlpineRuntime.shared

    override func exec(action: String, args: [Any], callback: Callback) {
        runtime.queue.async { [self] in
            do {
                switch action {
                case "isSupported": callback.success(true)
                case "isInstalled": callback.success(runtime.installed)
                case "isAxsRunning":
                    try runtime.shareFiles()
                    callback.success(runtime.serverID.flatMap { runtime.processes[$0] }.map { alpine_running($0.pid) } ?? false)
                case "install": try install(callback)
                case "backup", "restore", "uninstall", "clearBackup": try AlpineMaintenance.perform(action, callback: callback)
                case "startAxs":
                    try runtime.shareFiles()
                    if let id = runtime.serverID, let process = runtime.processes[id], alpine_running(process.pid) {
                        callback.success(); return
                    }
                    let command = args[safe: 0] as? Bool == true ? "exec /acode/axs -c sh" : "exec /bin/sh /acode/init-alpine.sh"
                    runtime.serverID = try runtime.start(command).id
                    callback.success()
                case "stopAxs":
                    if let id = runtime.serverID { runtime.stop(id) }
                    callback.success()
                default: callback.error("Unknown Alpine action: \(action)")
                }
            } catch { callback.error(error.localizedDescription) }
        }
    }

    private func install(_ callback: Callback) throws {
        try runtime.extract()
        try runtime.boot()
        let setup = """
        set -e
        printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf
        chmod +x /acode/axs
        ln -sf /acode/axs /usr/local/bin/axs
        /bin/sh /acode/init-alpine.sh --installing
        if ! apk info -e bash command-not-found tzdata wget >/dev/null; then
            rm -rf /acode/.configured
            exit 1
        fi
        """
        try runtime.start(setup, listener: { kind, text in
            callback.success(["type": kind, "data": text], keep: kind != "exit")
        })
    }
}
