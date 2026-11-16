#!/usr/bin/env python3
"""Local serial Ghidra worker. JSONL on stdin; @DISSECT@ JSONL on stdout.
Imported binaries are parsed, never executed. All project mutations live here.
"""
from __future__ import annotations
import argparse
import fcntl
import json
import os
from pathlib import Path
import queue
import shutil
import sys
import threading
import time
import traceback
from storage import (WorkspaceError, SCHEMA, plain_file, digest, atomic_json,
                     read_manifest, page_bounds, label, text_limit)

PREFIX = '@DISSECT@'
OUTPUT = threading.Lock()
PROTOCOL = sys.stdout

def emit(value):
    with OUTPUT:
        PROTOCOL.write(PREFIX + json.dumps(value, ensure_ascii=True) + '\n')
        PROTOCOL.flush()

class Cancelled(Exception):
    pass

class Engine:
    def __init__(self, install):
        self.install = Path(install).expanduser().resolve()
        self.started = False
        self.project = self.program = self.consumer = self.lock = self.root = None
        self.meta = {}
        self.undo_stack, self.redo_stack = [], []
        self.cancelled = set()
        self.active = None
        self.monitor = None
        self.guard = threading.Lock()

    def cancel(self, request_id):
        with self.guard:
            self.cancelled.add(request_id)
            if self.active == request_id and self.monitor is not None:
                self.monitor.cancel()

    def check(self):
        with self.guard:
            stopped = self.active in self.cancelled
        if stopped or (self.monitor is not None and self.monitor.isCancelled()):
            raise Cancelled('Operation cancelled. Previously saved work is preserved.')

    def progress(self, message):
        emit({'event': 'progress', 'id': self.active, 'message': message})

    def start(self):
        if self.started:
            return
        if not (self.install / 'Ghidra/application.properties').is_file():
            raise WorkspaceError('Ghidra folder is invalid. Run Set Up Engine or choose a Ghidra 12.2 installation.')
        self.progress('Starting local Ghidra engine…')
        import pyghidra
        self.py = pyghidra
        pyghidra.start(install_dir=self.install)
        from ghidra.framework import Application
        version = str(Application.getApplicationVersion())
        if version != '12.2':
            raise WorkspaceError(f'This preview requires Ghidra 12.2; found {version}.')
        import platform
        system = 'mac' if platform.system() == 'Darwin' else 'linux'
        arch = 'arm_64' if platform.machine() in ('arm64', 'aarch64') else 'x86_64'
        module = self.install / 'Ghidra/Features/Decompiler'
        candidates = [module / prefix / f'{system}_{arch}' / 'decompile' for prefix in ('build/os', 'os')]
        if not any(os.access(path, os.X_OK) for path in candidates):
            raise WorkspaceError('Native decompiler is missing or not executable. Run Set Up Engine again.')
        self.started = True

    def new_monitor(self):
        from ghidra.util.task import TaskMonitorAdapter
        with self.guard:
            self.monitor = TaskMonitorAdapter(True)
            if self.active in self.cancelled:
                self.monitor.cancel()

    def close(self):
        if self.program is not None:
            self.program.release(self.consumer)
        self.program = self.consumer = None
        if self.project is not None:
            self.project.close()
        self.project = None
        if self.lock is not None:
            self.lock.close()
        self.lock = self.root = None
        self.meta = {}
        self.undo_stack.clear()
        self.redo_stack.clear()

    def acquire(self, root):
        fd = os.open(root / '.dissect.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        stream = os.fdopen(fd, 'w')
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            stream.close()
            raise WorkspaceError('This workspace is already open in another Dissect window/process.')
        self.lock = stream
        self.root = root

    def attach(self):
        self.program, self.consumer = self.py.consume_program(self.project, '/Binary')

    def status(self):
        if self.program is None:
            return {'opened': False}
        return dict(self.meta, opened=True, path=str(self.root),
                    language=str(self.program.getLanguageID()),
                    compiler=str(self.program.getCompilerSpec().getCompilerSpecID()),
                    formatName=str(self.program.getExecutableFormat()),
                    functions=int(self.program.getFunctionManager().getFunctionCount()),
                    imageBase=str(self.program.getImageBase()),
                    canUndo=bool(self.undo_stack), canRedo=bool(self.redo_stack))

    def create(self, args):
        source = plain_file(args['source'])
        root = Path(args['workspace']).expanduser().absolute()
        if root.suffix != '.dissect' or root.exists() or root.is_symlink():
            raise WorkspaceError('Choose a new .dissect workspace name. Existing workspaces are never overwritten.')
        language = text_limit(args.get('language', ''), 128)
        compiler = text_limit(args.get('compiler', ''), 128)
        base = text_limit(args.get('imageBase', ''), 32)
        if base:
            try:
                base_value = int(base.removeprefix('0x'), 16)
                if not 0 <= base_value <= 0xffffffffffffffff:
                    raise ValueError()
            except ValueError:
                raise WorkspaceError('Image base must be a hexadecimal address, for example 08000000.')
        self.close()
        root.mkdir(parents=False)
        self.acquire(root)
        self.progress('Copying original binary…')
        shutil.copyfile(source, root / 'original.bin')
        os.chmod(root / 'original.bin', 0o600)
        self.meta = dict(schema=SCHEMA, format='dissect-workspace', name=source.name,
                         sha256=digest(root / 'original.bin'), size=(root / 'original.bin').stat().st_size,
                         program='/Binary', analysis='notStarted', created=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
        atomic_json(root / 'workspace.json', self.meta)
        (root / 'database').mkdir()
        self.project = self.py.open_project(str(root / 'database'), 'Dissect', create=True)
        self.progress('Importing binary…')
        loader = self.py.program_loader().project(self.project).source(str(root / 'original.bin')).name('Binary')
        if language:
            loader = loader.loaders('BinaryLoader').language(language)
            if compiler:
                loader = loader.compiler(compiler)
        self.check()
        with loader.load() as loaded:
            loaded.save(self.monitor)
        self.attach()
        if base:
            with self.py.transaction(self.program, 'Set image base'):
                self.program.setImageBase(self.address(base), True)
            self.program.save('Set image base', self.monitor)
        self.analyze({})
        return self.status()

    def open(self, args):
        root = Path(args['workspace']).expanduser().absolute()
        meta = read_manifest(root)
        self.close()
        self.acquire(root)
        self.meta = meta
        try:
            self.project = self.py.open_project(str(root / 'database'), 'Dissect')
            self.attach()
        except Exception:
            self.close()
            raise WorkspaceError('The Ghidra database could not open. It may be locked or the initial import did not finish.')
        return self.status()

    def require(self):
        if self.program is None:
            raise WorkspaceError('Open or import a binary first.')

    def analyze(self, args):
        self.require()
        self.progress('Analyzing binary — larger files can take several minutes…')
        self.meta['analysis'] = 'running'
        atomic_json(self.root / 'workspace.json', self.meta)
        try:
            self.py.analyze(self.program, self.monitor)
            # PyGhidra 3.2 cancels its monitor on normal completion too.
            # Preserve explicit user cancellation, but renew this consumed monitor.
            self.new_monitor()
            self.check()
            self.meta['analysis'] = 'complete'
        except Exception:
            self.meta['analysis'] = 'interrupted'
            raise
        finally:
            # Save partial analysis with a fresh uncancelled monitor so recovery is possible.
            self.program.save('Analysis checkpoint', self.py.task_monitor())
            atomic_json(self.root / 'workspace.json', self.meta)
        return self.status()

    def address(self, value):
        value = text_limit(value, 64)
        if value.lower().startswith('0x'):
            value = value[2:]
        addr = self.program.getAddressFactory().getAddress(value)
        if addr is None:
            raise WorkspaceError('Address is invalid for this program.')
        return addr

    def function_at(self, value):
        f = self.program.getFunctionManager().getFunctionContaining(self.address(value))
        if f is None:
            raise WorkspaceError('No function contains this address.')
        return f

    def index(self, args):
        self.require()
        offset, limit = page_bounds(args.get('offset', 0), args.get('limit', 200))
        kind = args.get('kind', 'functions')
        query = text_limit(args.get('query', ''), 256).casefold()
        if kind == 'functions':
            iterator = self.program.getFunctionManager().getFunctions(True)
            def convert(f):
                return {'address': str(f.getEntryPoint()), 'name': str(f.getName()),
                        'detail': str(f.getSignature().getPrototypeString()), 'kind': kind}
        elif kind == 'strings':
            from ghidra.program.model.data import StringDataInstance
            iterator = self.program.getListing().getDefinedData(True)
            def convert(d):
                if not StringDataInstance.isString(d):
                    return None
                s = StringDataInstance.getStringDataInstance(d).getStringValue()
                return {'address': str(d.getAddress()), 'name': str(s)[:2048], 'detail': str(d.getDataType().getName()), 'kind': kind}
        else:
            raise WorkspaceError('Unknown list kind.')
        rows, total = [], 0
        for item in iterator:
            self.check()
            row = convert(item)
            if row is None or (query and query not in (row['name'] + ' ' + row['address'] + ' ' + row['detail']).casefold()):
                continue
            if offset <= total < offset + limit:
                rows.append(row)
            total += 1
        return {'items': rows, 'total': total, 'offset': offset, 'hasMore': total > offset + len(rows)}

    def references(self, args):
        self.require()
        addr = self.address(args['address'])
        refs, manager = [], self.program.getReferenceManager()
        for ref in manager.getReferencesTo(addr):
            self.check()
            source = ref.getFromAddress()
            f = self.program.getFunctionManager().getFunctionContaining(source)
            refs.append({'address': str(source), 'name': str(f.getName()) if f else str(source),
                         'detail': str(ref.getReferenceType()), 'kind': 'reference'})
            if len(refs) == 1000:
                return {'items': refs, 'truncated': True}
        return {'items': refs, 'truncated': False}

    def function(self, args):
        self.require()
        f = self.function_at(args['address'])
        from ghidra.app.decompiler import DecompInterface
        decompiler = DecompInterface()
        code, warning = '', ''
        try:
            if not decompiler.openProgram(self.program):
                raise WorkspaceError('Decompiler could not open this program. Check that native components were built.')
            result = decompiler.decompileFunction(f, 45, self.monitor)
            self.check()
            if result.decompileCompleted() and result.getDecompiledFunction() is not None:
                code = str(result.getDecompiledFunction().getC())
            else:
                warning = str(result.getErrorMessage()) or 'Decompilation did not finish within 45 seconds.'
        finally:
            decompiler.dispose()
        lines, truncated = [], False
        for inst in self.program.getListing().getInstructions(f.getBody(), True):
            self.check()
            if len(lines) == 5000:
                truncated = True
                break
            lines.append(f'{inst.getAddress()}  {inst}')
        return {'address': str(f.getEntryPoint()), 'name': str(f.getName()),
                'signature': str(f.getSignature().getPrototypeString()), 'note': str(f.getComment() or ''),
                'code': code[:2_000_000], 'assembly': '\n'.join(lines),
                'warning': warning + ('\nAssembly limited to 5,000 instructions.' if truncated else '') + ('\nDecompiled output limited to 2 million characters.' if len(code) > 2_000_000 else '')}

    def bytes(self, args):
        self.require()
        start = self.address(args['address'])
        memory = self.program.getMemory()
        lines = []
        for row in range(16):
            self.check()
            octets = []
            for col in range(16):
                try:
                    addr = start.add(row * 16 + col)
                    if not memory.contains(addr):
                        break
                    octets.append(int(memory.getByte(addr)) & 255)
                except Exception:
                    break
            if not octets:
                break
            ascii_text = ''.join(chr(b) if 32 <= b < 127 else '.' for b in octets)
            lines.append(f'{start.add(row * 16)}  ' + ' '.join(f'{b:02x}' for b in octets).ljust(47) + '  ' + ascii_text)
        return {'text': '\n'.join(lines) or 'No initialized bytes at this address.'}

    def define(self, args):
        self.require()
        address = self.address(args['address'])
        if not self.program.getMemory().contains(address):
            raise WorkspaceError('This address is outside the imported memory image.')
        if self.program.getFunctionManager().getFunctionContaining(address) is not None:
            return self.status()
        from ghidra.app.cmd.disassemble import DisassembleCommand
        from ghidra.app.cmd.function import CreateFunctionCmd
        with self.py.transaction(self.program, 'Define function'):
            disassemble = DisassembleCommand(address, None, True)
            if not disassemble.applyTo(self.program, self.monitor):
                raise WorkspaceError(str(disassemble.getStatusMsg()) or 'Could not disassemble at this address.')
            create = CreateFunctionCmd(address)
            if not create.applyTo(self.program, self.monitor):
                raise WorkspaceError(str(create.getStatusMsg()) or 'Could not create a function at this address.')
            self.check()
        self.program.save('Define function', self.py.task_monitor())
        # Structural analysis changes delimit the small annotation undo history.
        self.undo_stack.clear()
        self.redo_stack.clear()
        return self.status()

    def apply_edit(self, operation, address, value):
        f = self.function_at(address)
        from ghidra.program.model.symbol import SourceType
        with self.py.transaction(self.program, 'Dissect ' + operation):
            if operation == 'rename':
                f.setName(label(value), SourceType.USER_DEFINED)
            elif operation == 'note':
                f.setComment(text_limit(value))
            elif operation == 'signature':
                from ghidra.app.util.cparser.C import CParserUtils
                from ghidra.app.cmd.function import ApplyFunctionSignatureCmd
                definition = CParserUtils.parseSignature(None, self.program, text_limit(value, 4096), False)
                if definition is None:
                    raise WorkspaceError('Could not parse this C function signature.')
                command = ApplyFunctionSignatureCmd(f.getEntryPoint(), definition, SourceType.USER_DEFINED)
                if not command.applyTo(self.program, self.monitor):
                    raise WorkspaceError(str(command.getStatusMsg()))
            else:
                raise WorkspaceError('Unknown edit operation.')
        self.program.save('Dissect ' + operation, self.py.task_monitor())

    def edit(self, args):
        self.require()
        f = self.function_at(args['address'])
        operation = args['operation']
        old = {'rename': str(f.getName()), 'note': str(f.getComment() or ''),
               'signature': str(f.getSignature().getPrototypeString())}.get(operation)
        if old is None:
            raise WorkspaceError('Unknown edit operation.')
        value = args['value']
        self.apply_edit(operation, str(f.getEntryPoint()), value)
        self.undo_stack.append((operation, str(f.getEntryPoint()), old, value))
        self.undo_stack = self.undo_stack[-100:]
        self.redo_stack.clear()
        return self.status()

    def undo(self, args):
        self.require()
        if not self.undo_stack:
            raise WorkspaceError('No change to undo.')
        item = self.undo_stack[-1]
        self.apply_edit(item[0], item[1], item[2])
        self.undo_stack.pop()
        self.redo_stack.append(item)
        return self.status()

    def redo(self, args):
        self.require()
        if not self.redo_stack:
            raise WorkspaceError('No change to redo.')
        item = self.redo_stack[-1]
        self.apply_edit(item[0], item[1], item[3])
        self.redo_stack.pop()
        self.undo_stack.append(item)
        return self.status()

    def languages(self, args):
        from ghidra.program.util import DefaultLanguageService
        rows = []
        for d in DefaultLanguageService.getLanguageService().getLanguageDescriptions(False):
            self.check()
            rows.append({'id': str(d.getLanguageID()), 'name': str(d.getDescription()),
                         'compilers': [str(c.getCompilerSpecID()) for c in d.getCompatibleCompilerSpecDescriptions()]})
        return {'languages': sorted(rows, key=lambda r: r['id'])}

    def execute(self, request):
        operation = request['method']
        allowed = {'create', 'open', 'analyze', 'index', 'function', 'references', 'bytes',
                   'edit', 'define', 'undo', 'redo', 'languages', 'status', 'doctor', 'close'}
        if operation not in allowed:
            raise WorkspaceError('Unknown engine operation.')
        self.start()
        self.new_monitor()
        self.check()
        args = request.get('params', {})
        if operation == 'doctor':
            from java.lang import System
            import platform
            return {'ghidra': '12.2', 'java': str(System.getProperty('java.version')),
                    'architecture': platform.machine(), 'python': platform.python_version()}
        if operation == 'status':
            return self.status()
        if operation == 'close':
            self.close()
            return {'opened': False}
        return getattr(self, operation)(args)


def serve(install):
    global PROTOCOL
    PROTOCOL = os.fdopen(os.dup(sys.stdout.fileno()), 'w', buffering=1)
    # Keep Java/native log writes out of the protocol pipe as well as Python logs.
    os.dup2(sys.stderr.fileno(), sys.stdout.fileno())
    engine = Engine(install)
    requests = queue.Queue(maxsize=100)
    def reader():
        try:
            while True:
                line = sys.stdin.buffer.readline(65538)
                if not line:
                    break
                if len(line) > 65536:
                    emit({'id': None, 'error': 'Request is too large.'})
                    break
                try:
                    request = json.loads(line)
                    if not isinstance(request, dict) or not isinstance(request.get('id'), str):
                        raise ValueError('Request requires a string id.')
                    if request.get('method') == 'cancel':
                        engine.cancel(request.get('params', {}).get('requestID'))
                    else:
                        requests.put_nowait(request)
                except Exception as e:
                    emit({'id': None, 'error': str(e)})
        finally:
            engine.cancel(engine.active)
            requests.put(None)
    threading.Thread(target=reader, daemon=True).start()
    try:
        while True:
            request = requests.get()
            if request is None:
                break
            engine.active = request['id']
            try:
                result = engine.execute(request)
                emit({'id': request['id'], 'result': result})
            except Exception as e:
                cancelled = isinstance(e, Cancelled) or request['id'] in engine.cancelled
                traceback.print_exc(file=sys.stderr)
                emit({'id': request['id'], 'error': 'Operation cancelled. Saved work is preserved.' if cancelled else str(e),
                      'cancelled': cancelled})
            finally:
                with engine.guard:
                    engine.cancelled.discard(request['id'])
                    engine.active = None
                    engine.monitor = None
    finally:
        engine.close()

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--ghidra', required=True)
    serve(p.parse_args().ghidra)
