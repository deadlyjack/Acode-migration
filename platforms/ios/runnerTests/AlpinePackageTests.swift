import XCTest
import WebKit

@MainActor
final class AlpinePackageTests: BridgeTestCase {
    func testNodeNpmAndLinuxSubprocesses() async throws {
        let webView = try await editorWebView()
        let result = try await webView.callAsyncJavaScript(#"""
            if (!await Terminal.isInstalled() && !await Terminal.install()) throw new Error(Terminal.lastInstallError);
            await Executor.execute('apk add --no-cache nodejs npm', true);
            const fs = acode.require('fs');
            const path = 'alpine://localhost/tmp/acode-node-probe.js';
            const code = `
                const assert = require('node:assert/strict');
                const fs = require('node:fs');
                const http = require('node:http');
                const child = require('node:child_process');
                assert.equal(1 + 2, 3);
                fs.writeFileSync('/tmp/acode-node-utf8', 'hello π');
                assert.equal(fs.readFileSync('/tmp/acode-node-utf8', 'utf8'), 'hello π');
                assert.equal(child.execFileSync('/bin/sh', ['-c', 'printf subprocess'], {encoding:'utf8'}), 'subprocess');
                const server = http.createServer((req, res) => res.end('loopback'));
                server.listen(0, '127.0.0.1', () => {
                    http.get('http://127.0.0.1:' + server.address().port, res => {
                        let body = '';
                        res.on('data', data => body += data);
                        res.on('end', () => {
                            assert.equal(body, 'loopback');
                            server.close(() => console.log('NODE_PASS'));
                        });
                    });
                });`;
            if (await fs(path).exists()) await fs(path).delete();
            await fs('alpine://localhost/tmp').createFile('acode-node-probe.js', code);
            const node = await Executor.execute('node /tmp/acode-node-probe.js', true);
            if (node !== 'NODE_PASS') throw new Error('Node check: ' + node);
            await Executor.execute('npm install --ignore-scripts --no-audit --no-fund --cache /tmp/acode-npm-cache --prefix /tmp/acode-npm-probe is-number@7.0.0', true);
            const npm = await Executor.execute('node -p "require(\'/tmp/acode-npm-probe/node_modules/is-number\')(42)"', true);
            if (npm !== 'true') throw new Error('npm package check: ' + npm);
            await Executor.execute('rm -rf /tmp/acode-node-probe.js /tmp/acode-node-utf8 /tmp/acode-npm-probe /tmp/acode-npm-cache', true);
            return {node, npm};
            """#, arguments: [:], in: nil, contentWorld: .page) as? [String: String]
        XCTAssertEqual(result?["node"], "NODE_PASS")
        XCTAssertEqual(result?["npm"], "true")
    }
}
