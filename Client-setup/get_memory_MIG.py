import subprocess
import re
import sys

def get_mig_memory_usage(pid: int) -> int:
    """
    Returns total GPU memory (in MiB) used by the given PID in MIG mode.
    """
    try:
        result = subprocess.run(
            ["nvidia-smi"], capture_output=True, text=True, check=True
        )
        output = result.stdout

        total_mem = 0
        for line in output.splitlines():
            # Match MIG process lines: PID and memory (e.g. 2824980 ... 410MiB)
            if str(pid) in line:
                match = re.search(r"(\d+)MiB", line)
                if match:
                    total_mem += int(match.group(1))
        return total_mem
    except Exception as e:
        print(f"Error: {e}")
        return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python mig_mem_usage.py <PID>")
        sys.exit(1)

    pid = int(sys.argv[1])
    mem_usage = get_mig_memory_usage(pid)
#    print(f"PID {pid} is using {mem_usage} MiB of GPU memory (MIG mode).")
    print(f"{mem_usage} MiB")
