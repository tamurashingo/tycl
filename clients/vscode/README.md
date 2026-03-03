# TyCL VS Code Extension

Visual Studio Code extension for TyCL (Typed Common Lisp) with LSP support.

## Features

- **Syntax Highlighting**: Highlight TyCL type annotations and keywords
- **Language Server Protocol**: Full LSP integration for intelligent editing
  - Code completion
  - Hover information
  - Diagnostics (errors and warnings)
  - Go to definition
  - Find references
  - Symbol renaming

## Prerequisites

- TyCL LSP server installed (`ros install tamurashingo/tycl`)

## Installation

### From Source

1. **Build the extension**:
   ```bash
   cd clients/vscode
   npm install
   npm run compile
   ```

2. **Install in VS Code**:
   ```bash
   npm run package  # Creates tycl-0.1.0.vsix
   code --install-extension tycl-0.1.0.vsix
   ```

### From Marketplace (Future)

```bash
code --install-extension tycl.tycl
```

## Configuration

Open VS Code settings (`File > Preferences > Settings`) and search for "TyCL", or edit `.vscode/settings.json` directly.

### Settings Reference

#### LSP Server

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `tycl.lsp.enabled` | boolean | `true` | Enable/disable TyCL Language Server |
| `tycl.lsp.executable` | string | `"tycl"` | TyCL executable name or path (installed via `ros install`) |
| `tycl.lsp.serverPath` | string | `""` | Path to TyCL source directory (for development only). When set, uses `roswell/tycl.ros` under this directory instead of the installed `tycl` command |
| `tycl.lsp.args` | string[] | `["lsp"]` | Arguments for TyCL LSP server. To enable Swank, add `"--swank"` and optionally a port number |
| `tycl.lsp.trace.server` | string | `"off"` | LSP communication tracing (`"off"`, `"messages"`, `"verbose"`) |

#### Diagnostics

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `tycl.diagnostics.debounceMs` | number | `500` | Delay in milliseconds before computing diagnostics after a change. Set to `0` for immediate diagnostics. Range: 0-5000 |

### Examples

#### Basic setup (TyCL installed via `ros install`)

```json
{
  "tycl.lsp.enabled": true
}
```

#### Development with local TyCL source

Set `tycl.lsp.serverPath` to the **TyCL project root directory** (the parent of the directory containing `roswell/tycl.ros`):

```
/home/user/projects/tycl/          <-- set this path
├── roswell/
│   └── tycl.ros
├── src/
└── ...
```

```json
{
  "tycl.lsp.serverPath": "/home/user/projects/tycl"
}
```

This runs `ros /home/user/projects/tycl/roswell/tycl.ros lsp` instead of the installed `tycl` command.

#### Custom executable path

```json
{
  "tycl.lsp.executable": "/custom/path/to/tycl"
}
```

#### Immediate diagnostics (no debounce)

```json
{
  "tycl.diagnostics.debounceMs": 0
}
```

#### Enable Swank server for REPL integration

```json
{
  "tycl.lsp.args": ["lsp", "--swank"]
}
```

With a custom port:

```json
{
  "tycl.lsp.args": ["lsp", "--swank", "9999"]
}
```

#### Enable verbose LSP tracing for debugging

```json
{
  "tycl.lsp.trace.server": "verbose"
}
```

## Usage

### Opening TyCL Files

1. Open any `.tycl` file
2. The extension activates automatically
3. LSP server starts in the background

### Features in Action

#### Type Information on Hover

Hover over any symbol to see its type:

```lisp
(defun [add :integer] ([x :integer] [y :integer])
  (+ x y))
```

Hovering over `add` shows: `(function (integer integer) integer)`

#### Code Completion

Start typing to get suggestions:

```lisp
(defun my-func ...
     ^ completion shows: defun, defmethod, defclass, etc.
```

#### Diagnostics

Errors appear in real-time:

```lisp
(defun [broken :invalid-type] ()  ; Error: Unknown type :invalid-type
  ...)
```

#### Go to Definition

- Right-click a symbol → "Go to Definition" (or `F12`)
- Jumps to where the symbol is defined

## Troubleshooting

### LSP Server Not Starting

1. **Check if TyCL is installed**:
   ```bash
   which tycl
   # or
   tycl help
   ```

2. **Test LSP server manually**:
   ```bash
   tycl lsp
   ```
   Should not output errors and wait for input.

3. **Enable LSP tracing**:
   ```json
   {
     "tycl.lsp.trace.server": "verbose"
   }
   ```
   Check Output panel (View > Output, select "TyCL Language Server").

### Syntax Highlighting Not Working

1. Verify file extension is `.tycl`
2. Check language mode (bottom-right corner of VS Code)
3. If not "TyCL", click and select "TyCL" from the list

### Extension Not Activating

1. Check extension is enabled: Extensions panel → search "TyCL"
2. Reload VS Code: `Ctrl+Shift+P` → "Developer: Reload Window"
3. Check developer console: `Ctrl+Shift+P` → "Developer: Toggle Developer Tools"

## Development

### Building from Source

```bash
npm install
npm run compile
```

### Watching for Changes

```bash
npm run watch
```

### Debugging

1. Open `clients/vscode` in VS Code
2. Press `F5` to launch Extension Development Host
3. Open a `.tycl` file in the new window

### Linting

```bash
npm run lint
```

## File Structure

```
clients/vscode/
├── package.json                 # Extension manifest
├── tsconfig.json                # TypeScript configuration
├── language-configuration.json  # Bracket matching, comments
├── syntaxes/
│   └── tycl.tmLanguage.json    # Syntax highlighting rules
└── src/
    └── extension.ts             # Extension entry point
```

## Contributing

Contributions welcome! Please submit issues or pull requests to the main TyCL repository.

## Related

- [TyCL Main Repository](https://github.com/tamurashingo/tycl)
- [Emacs Client](../emacs/README.md)

## License

MIT License - see LICENSE file in the main TyCL repository.
