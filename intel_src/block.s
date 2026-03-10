.intel_syntax noprefix
.section .data

.section .bss
    .lcomm colors, 12
    .comm x_cord, 4
    .comm y_cord, 4
    .extern rval    
    .extern gval
    .extern bval
    .extern renderer_ptr
    .globl x_cord
    .globl y_cord
.section .text
    .extern Rectangle
    .extern Color
    .extern SetGrid
    .extern GetGrid
    .extern rand_mod5
    .extern FillGrid
    .global DrawBlocks
    .global InitBlocks
    .global MoveLeft
    .global MoveRight
    .global MoveDown
    .global ShiftUp
InitBlocks:
    push rbp
    mov rbp, rsp
    mov DWORD PTR [rip + y_cord], 0
    mov DWORD PTR [rip + x_cord], 8
    call rand_mod5
    mov [rip + colors], eax
    call rand_mod5
    mov [rip + colors+4], eax
    call rand_mod5
    mov [rip + colors+8], eax
    mov rsp, rbp
    pop rbp
    ret
DrawBlocks:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    lea r13, [rip + colors]
    xor r12d, r12d
draw_loop:
    mov edi, DWORD PTR [r13 + r12*4]
    call Color
    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov esi, DWORD PTR [rip + rval]
    mov edx, DWORD PTR [rip + gval]
    mov ecx, DWORD PTR [rip + bval]
    mov r8d, 255
    call SDL_SetRenderDrawColor
    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov eax, DWORD PTR [rip + x_cord]
    imul eax, eax, 34
    add eax, 16
    mov esi, eax
    mov eax, DWORD PTR [rip + y_cord]
    add eax, r12d
    imul eax, eax, 18
    add eax, 16
    mov edx, eax
    mov ecx, 32
    mov r8d, 16
    call Rectangle
    inc r12d
    cmp r12d, 3
    jl draw_loop
    pop r13
    pop r12
    mov rsp, rbp
    pop rbp
    ret

MoveLeft:
    push rbp
    mov rbp, rsp
    
    mov eax, DWORD PTR [rip + x_cord]
    cmp eax, 0
    je left_over
    
    mov ecx, eax
    dec ecx
    mov edx, DWORD PTR [rip + y_cord]
    add edx, 2
    
    mov edi, edx
    mov esi, ecx
    call GetGrid
    
    cmp eax, -1
    jne left_over
    
    mov eax, DWORD PTR [rip + x_cord]
    dec eax
    mov [rip + x_cord], eax
    
left_over:
    mov rsp, rbp
    pop rbp
    ret

MoveRight:
    push rbp
    mov rbp, rsp
    
    mov eax, DWORD PTR [rip + x_cord]
    cmp eax, 17
    je right_over
    
    mov ecx, eax
    inc ecx
    mov edx, DWORD PTR [rip + y_cord]
    add edx, 2
    
    mov edi, edx
    mov esi, ecx
    call GetGrid
    
    cmp eax, -1
    jne right_over
    
    mov eax, DWORD PTR [rip + x_cord]
    inc eax
    mov [rip + x_cord], eax
    
right_over:
    mov rsp, rbp
    pop rbp
    ret

MoveDown:
    push rbp
    mov rbp, rsp
    mov edi, DWORD PTR [rip + y_cord]
    add edi, 3
    mov esi, DWORD PTR [rip + x_cord]
    call GetGrid
    cmp eax, -1
    jne merge_block
    mov edi, DWORD PTR [rip + y_cord]
    add edi, 3
    cmp edi, 24
    jg merge_block
    mov edi, [rip + y_cord]
    inc edi
    mov [rip + y_cord], edi
down_over:
    mov rsp, rbp
    pop rbp
    ret
merge_block:
    mov edi, DWORD PTR [rip + colors]
    mov edx, DWORD PTR [rip + x_cord]
    mov esi, DWORD PTR [rip + y_cord]
    cmp esi, 0
    je clearit
    call SetGrid
    
    mov edi, DWORD PTR [rip + colors+4]
    mov edx, DWORD PTR [rip + x_cord]
    mov esi, DWORD PTR [rip + y_cord]
    inc esi
    call SetGrid

    mov edi, DWORD PTR [rip + colors+8]
    mov edx, DWORD PTR [rip + x_cord]
    mov esi, DWORD PTR [rip + y_cord]
    add esi, 2
    call SetGrid

    call InitBlocks
    mov rsp, rbp
    pop rbp
    ret
clearit:
    call InitBlocks
    mov edi, -1
    call FillGrid
    mov rsp, rbp
    pop rbp
    ret
    
ShiftUp:
    push rbp
    mov rbp, rsp
    push rbx
    mov eax, DWORD PTR [rip + colors]
    mov ebx, DWORD PTR [rip + colors+4]
    mov ecx, DWORD PTR [rip + colors+8]
    mov [rip + colors], ecx
    mov [rip + colors+4], eax
    mov [rip + colors+8], ebx
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.section .note.GNU-stack,"",@progbits


