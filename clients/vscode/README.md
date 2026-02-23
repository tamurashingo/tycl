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

## Installation

### From Source

1. **Prerequisites**:
   - Node.js 18+ and npm
   - TyCL LSP server (see main TyCL README)

2. **Build the extension**:
   ```bash
   cd clients/vscode
   npm install
   npm run compile
   ```

3. **Install in VS Code**:
   ```bash
   npm run package  # Creates tycl-0.1.0.vsix
   code --install-extension tycl-0.1.0.vsix
   ```

### From Marketplace (Future)

```bash
code --install-extension tycl.tycl
```

## Configuration

Open VS Code settings (File > Preferences > Settings) and search for "TyCL":

### Basic Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `tycl.lsp.enabled` | `true` | Enable/disable TyCL Language Server |
| `tycl.lsp.executable` | `"ros"` | Roswell executable name or path |
| `tycl.lsp.serverPath` | `""` | Path to TyCL installation directory |
| `tycl.lsp.trace.server` | `"off"` | LSP communication tracing |

### Example: Using Local TyCL Installation

If you're running TyCL from source:

```json
{
  "tycl.lsp.serverPath": "/home/user/projects/tycl"
}
```

This will use `/home/user/projects/tycl/roswell/tycl.ros` as the LSP server.

### Example: Custom Roswell Path

```json
{
  "tycl.lsp.executable": "/usr/local/bin/ros"
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

1. **Check if Roswell is installed**:
   ```bash
   which ros
   # or
   ros version
   ```

2. **Test LSP server manually**:
   ```bash
   ros run roswell/tycl.ros lsp
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
