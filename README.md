Author: Daniel Scocco
Email: danielscocco@gmail.com
Site: http://www.programminglogic.com

Below you’ll find the code that runs a very simple operating system in ARM Assembly. On system start the OS will configure some pieces of hardware (e.g., GPT, UART and TZIC) and it will setup the environment (supervisor mode stacks, user stacks, etc).

The code obviously needs root privileges to run (so you can’t run it inside another OS), and the user code is supposed to be assembled on position 0x8000 to be executed correctly.

The OS enables multi-tasking by using the preemptive scheduling technique. Basically the GPT interrupts the OS every 100 cycles and the scheduler switches between processes. The OS also handles some syscalls (e.g., write, fork, getpid and exit).
