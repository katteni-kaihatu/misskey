// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
/// Offline fixture enabled only by UI tests; never reads a real account's store.
enum CompatibilityTestPage {
    static let html = """
    <!doctype html><html lang="ja"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>互換性テスト</title><style>body{font:20px system-ui;padding:20px;color:#111;background:#fff}button{display:block;padding:16px;margin:16px 0}</style>
    <h1>互換性テスト</h1>
    <input id="files" type="file" multiple hidden>
    <button onclick="document.getElementById('files').click()">添付を選択</button>
    <p id="selection">添付なし</p>
    <button onclick="exportFixture()">合成画像を書き出す</button>
    <button onclick="alert('ダイアログの確認')">alertを確認</button>
    <button onclick="document.getElementById('dialog').textContent=confirm('確認しますか？')?'承認':'取消済み'">confirmを確認</button>
    <p id="dialog"></p>
    <button onclick="negotiate()">ブリッジを確認</button><p id="bridge"></p>
    <script>
    document.getElementById('files').addEventListener('change', e => {
        document.getElementById('selection').textContent = e.target.files.length + '件選択';
    });
    function exportFixture() {
        const bytes = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAABLklEQVR4nO3RsQ3CMBiEUU/CPMyQOhuwITNQUmeNULtIFcmnE+/TDWD/b5yKNtIP+PcAhAMQbgJ4fUbFrj7z2L8VAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFQMAAAAAAAAAAAAAAAAAAAAAAAAAIH5ZAPnjAigYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACoGAAAAAAAAAAAAAAAAAAAAAAAAID7AFofgHAAwgEIByAcgHAAwgEINwO8R8cuOp5bxQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQMcAAAAAAAAAAAAAAAAAAAAAAAAAAEhfFkD+uAAKBgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOgYAAAAAAAAAAAAAAAAAAAAAAADgPoCWByAcgHAAwv0AQiF9XA9DnEcAAAAASUVORK5CYII='), c => c.charCodeAt(0));
        const href = URL.createObjectURL(new Blob([bytes], {type: 'image/png'}));
        const link = document.createElement('a');
        link.href = href; link.download = 'gridspace-ios-upload-test.png'; link.click();
        setTimeout(() => URL.revokeObjectURL(href), 60000);
    }
    async function negotiate() {
        try {
            const ready = await window.gridspaceNative.handshake('offline-fixture');
            document.getElementById('bridge').textContent = ready.status === 'success' ? 'ブリッジ接続済み' : 'ブリッジ拒否';
        } catch { document.getElementById('bridge').textContent = 'ブリッジ拒否'; }
    }
    </script></html>
    """
}
#endif
