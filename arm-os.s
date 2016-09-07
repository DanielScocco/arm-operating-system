onfigurable STACK values for each ARM core operation mode
.set USR_STACK, 0x11000
.set SVC_STACK, 0x10800
.set UND_STACK, 0x07c00
.set ABT_STACK, 0x07800
.set FIQ_STACK, 0x07400
.set IRQ_STACK, 0x07000

@--Interruption Vector
.org 0x0
b systemStart
.org 0x8
b swInterruption
.org 0x18
b gptInterruption

@-----------------System start/reset------------------@
.org 0x20
systemStart:

@--Set CPSR to Supervisor mode, IRQ/FIQ disabled
msr CPSR_c, #0xD3 

@---------------GPT CONFIGURATION---------------------@
@--Enable GPT and set Clock Source
mov r0, #0x41
ldr r1, =0x53FA0000
str r0, [r1]

@--Set GPT_OCR1 to 100
mov r0, #0x64
ldr r1, =0x53FA0010
str r0, [r1]

@--Enable Channel 1 Interruptions
mov r0, #1
ldr r1, =0x53FA000C
str r0, [r1]

@---------------TZIC CONFIGURATION--------------------@
@--TZIC interruption 39 as non-secure
ldr r1, =0x0FFFC000
mov r0, #(1<<7)
str r0, [r1, #0x84]

@--TZIC enable interruption 39
str r0, [r1, #0x104]

@--TZIC configure interrupt 39 priority as 1
ldr r0, [r1, #0x424]
bic r0, r0, #0xFF000000
mov r2, #1
orr r0, r0, r2, lsl #24
str r0, [r1, #0x424]

@--TZIC configure PRIOMASK as 0
eor r0, r0, r0
str r0, [r1, #0xC]

@--TZIC enable interruptions controller
mov r0, #1
str r0, [r1, #0x0]

@----------------UART CONFIGURATION------------------@
@--Enable UART
ldr r1, =0x53FBC080
mov r0, #1
str r0, [r1]
@--Set hardware flow control, data format and enable trans/receiver
ldr r0, =0x2127
str r0, [r1, #4]!
@--Set UCR3[RXDMUXSEL] = 1
ldr r0, =0x0704
str r0, [r1, #4]!
@--Set CTS trigger level to 31
ldr r0, =0x7C00
str r0, [r1, #4]!
@--Set internal clock divider = 5
ldr r0, =0x089E
str r0, [r1, #4]!
@--Set baud rate to 921.6kbps
ldr r0, =0x08FF
str r0, [r1, #20]!
ldr r0, =0x0C34
str r0, [r1, #4]

@--Initializa Stack Points of All Modes
mov sp, #SVC_STACK 
msr CPSR_c, #0xDF  @ Enter system mode, FIQ/IRQ disabled
mov sp, #USR_STACK
msr CPSR_c, #0xD1  @ Enter FIQ mode, FIQ/IRQ disabled
mov sp, #FIQ_STACK
msr CPSR_c, #0xD2  @ Enter IRQ mode, FIQ/IRQ disabled
mov sp, #IRQ_STACK
msr CPSR_c, #0xD7  @ Enter abort mode, FIQ/IRQ disabled
mov sp, #ABT_STACK
msr CPSR_c, #0xDB  @ Enter undefined mode, FIQ/IRQ disabled
mov sp, #UND_STACK

@--Initialize array of active processes
ldr r1, =activeProcesses
@--Process 0 is active
mov r0, #1
strb r0, [r1], #1
@--All others are inactive
mov r0, #0
mov r2, #7
loop1:
  cmp r2, #0
  beq endLoop1
  strb r0, [r1], #1
  sub r2, r2, #1
  b loop1
endLoop1:

@--Set currentProcess=0
ldr r1, =currentProcess
mov r0, #0
str r0, [r1]

@--Change to User mode, enable interrupts  and Jump to user code
msr CPSR_c, #0x10
mov pc, #0x8000

@----------------GPT Interruption Handler------------@
gptInterruption:
  @-Set GPT_SR to 1 to acknowledge interruption
  ldr r1, =0x53FA0008
  mov r0, #1
  str r0, [r1]
  @-Jump to Main Scheduler
  b mainSchedulerSaveFirst

@---------------SW Interruption---------------------@
swInterruption:
  @-Set CPSR to Supervisor mode, IRQ/FIQ disabled
  msr CPSR_c, #0xD3
  @-Check syscall number
  cmp r7, #4
  beq writeSyscall
  cmp r7, #1
  beq exitSyscall
  cmp r7, #2
  beq forkSyscall
  cmp r7, #20
  beq getpidSyscall

  @------Write Syscall
  writeSyscall:
  push {r4-r6}
  ldr r3, =0x53FBC094
  ldr r5, =0x53FBC040
  mov r0, r2
  mov r0, #(1<<13)
  writeLoop:
    cmp r2, #0
    beq doneWriting
    @--Wait for the transmission queue be ready
    transmitterLoop:
      ldr r4, [r3]
      and r4, r4, r0
      cmp r4, #0
      beq transmitterLoop
    ldrb r6, [r1], #1
    strb r6, [r5]
    sub r2, r2, #1
    b writeLoop
  doneWriting:
  pop {r4-r6}
  b exitSwInterruption

  @-----GetPid Syscall
  getpidSyscall:
  ldr r0, =currentProcess
  ldr r0, [r0]
  add r0, r0, #1
  b exitSwInterruption

  @-----Fork Syscall
  forkSyscall:
  push {r1-r3}
  @-Find available id to fork
  mov r0, #0
  ldr r1, =activeProcesses
  findLoop:
    cmp r0, #8
    beq noProcessAvailable
    ldrb r3, [r1, r0]
    cmp r3, #0
    beq foundAvailable
    add r0, r0, #1
    b findLoop
  foundAvailable:
  @-Mark process id as active
  mov r2, #1
  strb r2, [r1, r0]
  @-Save return address
  ldr r1, =returnArray
  str r14, [r1, r0, lsl #2]
  @-Get address of contexts array
  ldr r1, =p1context
  @-Move to right process context
  add r1, r1, r0, lsl #6
  @-Save CPSR
  mrs r2, SPSR
  str r2, [r1], #4
  @-Save Registers r0-r3
  mov r2, #0
  str r2, [r1], #4
  pop {r2}
  str r2, [r1], #4
  pop {r2}
  str r2, [r1], #4
  pop {r2}
  str r2, [r1], #4
  @-Save Registers r4-r12
  mov r2, r4
  str r2, [r1], #4
  mov r2, r5
  str r2, [r1], #4
  mov r2, r6
  str r2, [r1], #4
  mov r2, r7
  str r2, [r1], #4
  mov r2, r8
  str r2, [r1], #4
  mov r2, r9
  str r2, [r1], #4
  mov r2, r10
  str r2, [r1], #4
  mov r2, r11
  str r2, [r1], #4
  mov r2, r12
  str r2, [r1], #4
  @----Set r13 appropriately
  push {r4-r8}
  ldr r2, =currentProcess
  ldr r2, [r2]
  @-Point r3 to stack of children process
  ldr r3, =0x11000
  sub r3, r3, r0, lsl #12
  @-Poiont r4 to stack of parent process
  ldr r4, =0x11000
  sub r4, r4, r2, lsl #12
  @-Go to System Mode to recover r13 and r14
  msr CPSR_c, #0xDF   
  mov r5, r13
  mov r6, r14
  @-Back to Supervidor Mode
  msr CPSR_c, #0xD3
  @-Loop to copy over stack
  CopyStack:
    cmp r4, r5
    blt doneCopyingStack
    ldr r7, [r4], #-4
    str r7, [r3], #-4
    b CopyStack
  doneCopyingStack:
  @-Adjust stack pointer
  add r3, r3, #4
  @-Save r13 and r14 on context array
  str r3, [r1], #4
  str r6, [r1]
  pop {r4-r8}

  @-Increment process id (1-indexed instead of 0-indexed) and return
  add r0, r0, #1
  b exitSwInterruption  

  noProcessAvailable:
  mov r0, #-1
  b exitSwInterruption    

  @-----Exit Syscall
  exitSyscall:
  @-Get currentProcess id
  ldr r0, =currentProcess
  ldr r0, [r0]
  @-Mark id as inactive on array
  ldr r1, =activeProcesses
  add r1, r1, r0
  mov r0, #0
  strb r0, [r1]
  @-Jump to scheduler
  b mainScheduler

  exitSwInterruption:
  movs pc, lr

@--------------Main Scheduler-------------------------@
@-Coming from GPT interruption, save context first
mainSchedulerSaveFirst:
  push {r0-r3}
  @-Save return address
  ldr r0, =currentProcess
  ldr r0, [r0]
  ldr r1, =returnArray
  sub r14, r14, #4
  str r14, [r1, r0, lsl #2]
  @-Get address of contexts array
        ldr r1, =p1context
        @-Move to right process context
  ldr r0, =currentProcess
  ldr r0, [r0]
        add r1, r1, r0, lsl #6
        @-Save CPSR
        mrs r2, SPSR
        str r2, [r1], #4
        @-Save Registers r0-r3
        pop {r2}
        str r2, [r1], #4
        pop {r2}
        str r2, [r1], #4
        pop {r2}
        str r2, [r1], #4
        pop {r2}
        str r2, [r1], #4
        @-Save Registers r4-r12
        mov r2, r4
        str r2, [r1], #4
        mov r2, r5
        str r2, [r1], #4
        mov r2, r6
        str r2, [r1], #4
        mov r2, r7
        str r2, [r1], #4
        mov r2, r8
        str r2, [r1], #4
        mov r2, r9
        str r2, [r1], #4
        mov r2, r10
        str r2, [r1], #4
        mov r2, r11
        str r2, [r1], #4
        mov r2, r12
        str r2, [r1], #4
  @-Go to System Mode to recover r13 and r14
        msr CPSR_c, #0xDF   
        mov r2, r13
        mov r3, r14
        @-Back to IRQ Mode
        msr CPSR_c, #0x92
  @-Save registers r13 and r14
  str r2, [r1], #4
  str r3, [r1]
  
  @-Back to Supervisor
        msr CPSR_c, #0xD3

mainScheduler:
  ldr r0, =currentProcess
  ldr r1, [r0]
  ldr r0, =activeProcesses
  mov r2, #8
  traverseArray:
    cmp r2, #0
    beq endTraversal
    cmp r1, #7
    moveq r1, #0
    addne r1, r1, #1
    ldrb r3, [r0, r1]
    cmp r3, #1
    @-if equal go to this process, changing currentProcess first
    beq changeProcess
    sub r2, r2, #1
    b traverseArray
  endTraversal:
  @--No more user processes to run, wait for interruption
  infiniteLoop:
    b infiniteLoop
  @--Change process and return execution to it
  changeProcess:
  ldr r0, =currentProcess
  str r1, [r0]
  @-Set return address on r14
  ldr r0, =returnArray
  ldr r2, [r0, r1, lsl #2]
  mov r14, r2
  @-Restore registers r14 and r13
  ldr r0, =p1context
  add r0, r0, r1, lsl #6
  add r0, r0, #60
  ldr r2, [r0], #-4
  ldr r3, [r0], #-4
  @-Change to System Mode
  msr CPSR_c, #0xDF
  mov r14, r2
  mov r13, r3
  @-Back to Supervisor
  msr CPSR_c, #0xD3
  @-Restore registers r12-r4
  ldr r2, [r0], #-4
  mov r12, r2
  ldr r2, [r0], #-4
        mov r11, r2
  ldr r2, [r0], #-4
        mov r10, r2
  ldr r2, [r0], #-4
        mov r9, r2
  ldr r2, [r0], #-4
        mov r8, r2
  ldr r2, [r0], #-4
        mov r7, r2
  ldr r2, [r0], #-4
        mov r6, r2
  ldr r2, [r0], #-4
        mov r5, r2
  ldr r2, [r0], #-4
        mov r4, r2
  @-Restore SPSR
  ldr r2, =p1context
  add r2, r2, r1, lsl #6
  ldr r3, [r2]
  msr SPSR, r3
  @-Restore registers r3-r0
  ldr r1, [r0], #-4
  mov r3, r1
  ldr r1, [r0], #-4
  mov r2, r1
  ldr r1, [r0], #-4
  ldr r0, [r0]
  @-Return execution to this process
  movs pc, lr

.ltorg

@--Interruption mode stacks
.org 0x6C00
irqStack: .space 1024
fiqStack: .space 1024
abtStack: .space 1024
undStack: .space 1024

@--User software goes in this memory range

@--User and supervisor mode stacks
.org 0x9000
p8supervisor: .space 2048
p8user: .space 2048
p7supervisor: .space 2048
p7user: .space 2048
p6supervisor: .space 2048
p6user: .space 2048
p5supervisor: .space 2048
p5user: .space 2048
p4supervisor: .space 2048
p4user: .space 2048
p3supervisor: .space 2048
p3user: .space 2048
p2supervisor: .space 2048
p2user: .space 2048
p1supervisor: .space 2048
p1user: .space 2048

@--Array to hold saved contexts
.org 0x12000
p1context: .space 512

@--Array to hold return addresses
.org 0x13000
returnArray: .space 32

@--CurrentProcess variable and array to store list of active ones
currentProcess: .space 4
activeProcesses: .space 8
