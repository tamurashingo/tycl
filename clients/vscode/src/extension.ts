import * as path from 'path';
import * as fs from 'fs';
import { workspace, ExtensionContext, window } from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  Executable,
  Trace
} from 'vscode-languageclient/node';

let client: LanguageClient;

export function activate(context: ExtensionContext) {
  const config = workspace.getConfiguration('tycl');
  
  if (!config.get<boolean>('lsp.enabled', true)) {
    return;
  }

  const serverPath = config.get<string>('lsp.serverPath', '');
  let executable = config.get<string>('lsp.executable', 'tycl');
  let args = config.get<string[]>('lsp.args', ['lsp']);

  // If serverPath is specified, adjust the command to use absolute path
  if (serverPath) {
    const tyClScript = path.join(serverPath, 'roswell', 'tycl.ros');
    if (!fs.existsSync(tyClScript)) {
      window.showErrorMessage(
        `TyCL LSP: tycl.ros not found at ${tyClScript}. Please check tycl.lsp.serverPath setting.`
      );
      return;
    }
    // Use ros to run the local script
    executable = 'ros';
    args = ['run', tyClScript, 'lsp'];
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
    }
  };

  client = new LanguageClient(
    'tyClLanguageServer',
    'TyCL Language Server',
    serverOptions,
    clientOptions
  );

  const trace = config.get<string>('lsp.trace.server', 'off');
  if (trace === 'verbose') {
    client.setTrace(Trace.Verbose);
  } else if (trace === 'messages') {
    client.setTrace(Trace.Messages);
  } else {
    client.setTrace(Trace.Off);
  }

  client.start();

  window.showInformationMessage('TyCL Language Server started');
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
