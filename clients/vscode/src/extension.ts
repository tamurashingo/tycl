import * as path from 'path';
import * as fs from 'fs';
import { workspace, ExtensionContext, window, OutputChannel } from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  Executable,
  Trace
} from 'vscode-languageclient/node';

let client: LanguageClient;
let outputChannel: OutputChannel;

export function activate(context: ExtensionContext) {
  // Create output channel for debug message
  outputChannel = window.createOutputChannel('TyCL Language Server');
  outputChannel.appendLine('[TyCL] Extension activating...');

  const config = workspace.getConfiguration('tycl');
  
  if (!config.get<boolean>('lsp.enabled', true)) {
    outputChannel.appendLine('[TyCL] LSP is disabled in settings');
    return;
  }

  const serverPath = config.get<string>('lsp.serverPath', '');
  let executable = config.get<string>('lsp.executable', 'tycl');
  let args = config.get<string[]>('lsp.args', ['lsp']);

  outputChannel.appendLine(`[TyCL] Server path: ${serverPath || '(use PATH)'}`);
  outputChannel.appendLine(`[TyCL] Executable: ${executable}`);
  outputChannel.appendLine(`[TyCL] Args ${JSON.stringify(args)}`);

  // If serverPath is specified, adjust the command to use absolute path
  if (serverPath) {
    const tyClScript = path.join(serverPath, 'tycl.ros');
    outputChannel.appendLine(`[TyCL] Cheking for script: ${tyClScript}`);
    if (!fs.existsSync(tyClScript)) {
      const errorMsg = `TyCL LSP: tycl.ros not found at ${tyClScript}. Please check tycl.lsp.serverPath setting.`;
      outputChannel.appendLine(`[TyCL] ERROR: ${errorMsg}`);
      window.showErrorMessage(errorMsg);
      return;
    }
    // Use ros to run the local script
    executable = 'ros';
    args = [tyClScript, 'lsp'];
    outputChannel.appendLine(`[TyCL] Using development mode: ${tyClScript} lsp`);
  }

  const serverExecutable: Executable = {
    command: executable,
    args: args,
    options: {}
  };

  const serverOptions: ServerOptions = {
    run: serverExecutable,
    debug: serverExecutable
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'tycl' }],
    synchronize: {
      fileEvents: workspace.createFileSystemWatcher('**/*.tycl')
    },
    outputChannel: outputChannel,
    traceOutputChannel: outputChannel
  };

  client = new LanguageClient(
    'tyClLanguageServer',
    'TyCL Language Server',
    serverOptions,
    clientOptions
  );

  const trace = config.get<string>('lsp.trace.server', 'off');
  outputChannel.appendLine(`[TyCL] Trace level: ${trace}`);
  if (trace === 'verbose') {
    client.setTrace(Trace.Verbose);
  } else if (trace === 'messages') {
    client.setTrace(Trace.Messages);
  } else {
    client.setTrace(Trace.Off);
  }

  // Log client lifecycle events
  client.onDidChangeState((event) => {
    outputChannel.appendLine(`[TyCL] State changed: ${event.oldState} -> ${event.newState}`);
  });

  outputChannel.appendLine('[TyCL] Starting language server...');
  client.start().then(
    () => {
      outputChannel.appendLine('[TyCL] Language server started successfully');
      window.showInformationMessage('TyCL Language Server started');
    },
    (error) => {
      outputChannel.appendLine(`[TyCL] ERROR: Failed to start language server: ${error}`);
      window.showErrorMessage(`TyCL LSP failed to start: ${error}`);
    }
  );
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    outputChannel?.appendLine('[TyCL] Deactivating (no client)');
    return undefined;
  }
  outputChannel?.appendLine('[TyCL] Stopping language server...');
  return client.stop().then(
    () => {
      outputChannel?.appendLine('[TyCL] Language server stopped');
      outputChannel?.dispose();
    },
    (error) => {
      outputChannel?.appendLine(`[TyCL] ERROR stopping server: ${error}`);
      outputChannel?.dispose();
    }
  );
}
