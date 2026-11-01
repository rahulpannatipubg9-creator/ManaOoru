"""Run the opt-in probe on the isolated Android package and retain raw evidence."""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--package', default='com.manaooru.pad7bench')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--fps', type=int, default=60)
parser.add_argument('--drive-seconds', type=int, default=180)
parser.add_argument('--idle-seconds', type=int, default=60)
parser.add_argument('--soak', action='store_true')
parser.add_argument('--patch', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
adb = ['adb', '-s', args.serial]

def run(*command, binary=False):
    result = subprocess.run(adb + list(command), capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace') + result.stdout.decode(errors='replace'))
    return result.stdout if binary else result.stdout.decode(errors='replace')

config = dict(fps=args.fps, drive_seconds=args.drive_seconds,
              idle_seconds=args.idle_seconds, soak=args.soak, run_id=time.time_ns())
config_path = args.output / 'config.json'
config_path.write_text(json.dumps(config))
run('shell', 'am', 'force-stop', args.package)
run('shell', 'run-as', args.package, 'mkdir', '-p', 'files')
if args.patch:
    run('push', str(args.patch), '/data/local/tmp/pad7bench_patch.pck')
    run('shell', 'run-as', args.package, 'cp', '/data/local/tmp/pad7bench_patch.pck', 'files/pad7_patch.pck')
else:
    run('shell', 'run-as', args.package, 'rm', '-f', 'files/pad7_patch.pck')
for source, destination in [(Path(__file__).with_name('pad7_device_probe.gd'), 'stress_test.gd'),
                            (config_path, 'pad7_config.json')]:
    remote = '/data/local/tmp/pad7bench_' + destination
    run('push', str(source), remote)
    run('shell', 'run-as', args.package, 'cp', remote, 'files/' + destination)
with (args.output / 'godot.log').open('wb') as log:
    logger = subprocess.Popen(adb + ['logcat', '-T', '1', '-s', 'godot:V', 'AndroidRuntime:E'],
                              stdout=log, stderr=subprocess.STDOUT)
    try:
        print(run('shell', 'am', 'start', '-n', args.package + '/com.godot.game.GodotAppLauncher'), flush=True)
        start = time.monotonic()
        seen = set()
        while time.monotonic() - start < args.drive_seconds + args.idle_seconds + 500:
            elapsed = round(time.monotonic() - start)
            for name, command in [('battery', ['shell', 'dumpsys', 'battery']),
                                  ('thermal', ['shell', 'dumpsys', 'thermalservice']),
                                  ('memory', ['shell', 'dumpsys', 'meminfo', args.package])]:
                data = run(*command)
                (args.output / f'{elapsed:04}_{name}.txt').write_text(data)
            contents = (args.output / 'godot.log').read_text(errors='replace')
            for line in contents.splitlines():
                if any(token in line for token in ['PAD7_CONTEXT', 'PAD7_RESULT', 'PAD7_ROUTE', 'PAD7_COMPLETE', 'PAD7_FAIL', 'SCRIPT ERROR']):
                    if line not in seen:
                        print(line, flush=True)
                        seen.add(line)
            print(f'HOST_CHECKPOINT seconds={elapsed}', flush=True)
            process = subprocess.run(adb + ['shell', 'pidof', args.package], capture_output=True)
            if elapsed > 10 and not process.stdout.strip():
                print('APP_EXITED: preserving Android exit reason', flush=True)
                break
            if 'PAD7_COMPLETE' in contents or 'PAD7_FAIL' in contents or 'SCRIPT ERROR' in contents:
                break
            time.sleep(30)
        else:
            print('Probe timeout; partial evidence retained', flush=True)
        (args.output / 'exit-info.txt').write_text(run('shell', 'dumpsys', 'activity', 'exit-info', args.package))
        result = subprocess.run(adb + ['exec-out', 'run-as', args.package, 'cat', 'files/pad7_results.json'], capture_output=True)
        if result.returncode == 0:
            payload = json.loads(result.stdout)
            if payload.get('config', {}).get('run_id') == config['run_id']:
                (args.output / 'results.json').write_bytes(result.stdout)
            else:
                print('Ignoring stale results from a previous run', flush=True)
        screenshot = run('exec-out', 'screencap', '-p', binary=True)
        (args.output / 'final-screen.png').write_bytes(screenshot)
    finally:
        logger.terminate()
        logger.wait(timeout=10)
