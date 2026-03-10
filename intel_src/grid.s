.intel_syntax noprefix
.section .data

.section .bss
    .lcomm rect1, 16
    .lcomm grid, 1800
    .comm rval, 4
    .comm gval, 4
    .comm bval, 4
    .extern renderer_ptr
    .extern score
    .globl rval
    .globl gval
    .globl bval
.section .text
    .extern SDL_SetRenderDrawColor
    .extern SDL_RenderFillRect
    .extern InitBlocks
    .extern DrawBlocks
    .global Rectangle
    .global DrawGrid
    .global FillGrid
    .global SetGrid
    .global GetGrid
    .global CheckGrid
    .global CheckMoveDown
    .global rand_mod5
    .global Color
FillGrid:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov r12d, 0
    mov DWORD PTR [rip + score], 0
fill_y:
    mov r13d, 0
fill_x:
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    call SetGrid
    inc r13d
    cmp r13d, 18
    jl fill_x
    inc r12d
    cmp r12d, 25
    jl fill_y
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret
Color:
    push rbp
    mov rbp, rsp
    cmp edi, -1
    je set_black
    cmp edi, 0
    je set_c1
    cmp edi, 1
    je set_c2
    cmp edi, 2
    je set_c3
    cmp edi, 3
    je set_c4
    cmp edi, 4
    je set_c5
    jmp over
set_c1:  
    mov DWORD PTR [rip + rval], 255
    mov DWORD PTR [rip + gval], 0
    mov DWORD PTR [rip + bval], 0
    jmp over
set_c2:
    mov DWORD PTR [rip + rval], 0
    mov DWORD PTR [rip + gval], 255
    mov DWORD PTR [rip + bval], 0
    jmp over
set_c3:
    mov DWORD PTR [rip + rval], 0
    mov DWORD PTR [rip + gval], 0
    mov DWORD PTR [rip + bval], 255
    jmp over
set_c4:
    mov DWORD PTR [rip + rval], 255
    mov DWORD PTR [rip + gval], 255
    mov DWORD PTR [rip + bval], 0
    jmp over
set_c5:
    mov DWORD PTR [rip + rval], 255
    mov DWORD PTR [rip + gval], 0
    mov DWORD PTR [rip + bval], 255
    jmp over
set_black:
    mov DWORD PTR [rip + rval], 0
    mov DWORD PTR [rip + gval], 0
    mov DWORD PTR [rip + bval], 0
    jmp over
over:
    mov rsp, rbp
    pop rbp
    ret

Rectangle:
    push rbp
    mov rbp, rsp
    mov [rip + rect1], esi
    mov [rip + rect1+4], edx
    mov [rip + rect1+8], ecx
    mov [rip + rect1+12], r8d
    mov rdi, QWORD PTR [rip + renderer_ptr]
    lea rsi, [rip + rect1]
    call SDL_RenderFillRect
    leave
    ret
DrawGrid:
    push rbp
    mov rbp, rsp
    sub rsp, 128
    mov [rip + renderer_ptr], rdi
    mov DWORD PTR [rbp + -8], 16
    mov DWORD PTR [rbp + -24], 0
grid_loop_y:
    mov DWORD PTR [rbp + -16], 16
    mov DWORD PTR [rbp + -28], 0
grid_loop_x:  
    mov edi, DWORD PTR [rbp + -24]
    mov esi, DWORD PTR [rbp + -28]
    call GetGrid
    mov edi, eax
    call Color
    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov esi, DWORD PTR [rip + rval]
    mov edx, DWORD PTR [rip + gval]
    mov ecx, DWORD PTR [rip + bval]
    mov r8d, 255
    call SDL_SetRenderDrawColor
    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov esi, DWORD PTR [rbp + -16]
    mov edx, DWORD PTR [rbp + -8]
    mov ecx, 32
    mov r8d, 16
    call Rectangle
nocolor:
    add DWORD PTR [rbp + -16], 34
    inc DWORD PTR [rbp + -28]
    cmp DWORD PTR [rbp + -28], 18
    jl grid_loop_x
    add DWORD PTR [rbp + -8], 18
    inc DWORD PTR [rbp + -24]
    cmp DWORD PTR [rbp + -24], 25
    jl grid_loop_y
    leave
    ret
rand_mod5:
    push rbp
    mov rbp, rsp
    call rand
    mov ecx, 5
    cdq
    idiv ecx
    mov eax, edx
    mov rsp, rbp
    pop rbp
    ret



GetGrid:
    push rbp
    mov rbp, rsp
    lea r8, [rip + grid]
    imul eax, edi, 18
    add eax, esi
    shl eax, 2
    mov ecx, DWORD PTR [r8 + rax*1]
    mov eax, ecx
    mov rsp, rbp
    pop rbp
    ret


SetGrid:
    push rbp
    mov rbp, rsp
    lea r8, [rip + grid]
    imul eax, esi, 18
    add eax, edx
    shl eax, 2
    mov [r8 + rax*1], edi
    mov rsp, rbp
    pop rbp
    ret



CheckGrid:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    sub rsp, 8
    mov eax, 0
    mov r12d, 0
y_loop_check:
    mov r13d, 0
x_loop_check:
    mov edi, r12d
    mov esi, r13d
    call GetGrid
    mov r14d, eax

    cmp r14d, -1
    jle next_iteration

    cmp r13d, 16
    jge check_vertical
    mov edi, r12d
    mov esi, r13d
    add esi, 1
    call GetGrid
    cmp eax, r14d
    jne check_vertical
    mov edi, r12d
    mov esi, r13d
    add esi, 2
    call GetGrid
    cmp eax, r14d
    jne check_vertical
    jmp horizontal_match_found
check_vertical:
    cmp r12d, 23
    jge check_diagonal_dr
    mov edi, r12d
    add edi, 1
    mov esi, r13d
    call GetGrid
    cmp eax, r14d
    jne check_diagonal_dr
    mov edi, r12d
    add edi, 2
    mov esi, r13d
    call GetGrid
    cmp eax, r14d
    jne check_diagonal_dr
    jmp vertical_match_found

check_diagonal_dr: 
    cmp r12d, 23
    jge check_diagonal_dl
    cmp r13d, 16
    jge check_diagonal_dl
    mov edi, r12d
    add edi, 1
    mov esi, r13d
    add esi, 1
    call GetGrid
    cmp eax, r14d
    jne check_diagonal_dl
    mov edi, r12d
    add edi, 2
    mov esi, r13d
    add esi, 2
    call GetGrid
    cmp eax, r14d
    jne check_diagonal_dl
    jmp diagonal_dr_match_found

check_diagonal_dl: 
    cmp r12d, 23
    jge next_iteration
    cmp r13d, 2
    jl next_iteration
    mov edi, r12d
    add edi, 1
    mov esi, r13d
    sub esi, 1
    call GetGrid
    cmp eax, r14d
    jne next_iteration
    mov edi, r12d
    add edi, 2
    mov esi, r13d
    sub esi, 2
    call GetGrid
    cmp eax, r14d
    jne next_iteration
    jmp diagonal_dl_match_found

next_iteration:
    inc r13d
    cmp r13d, 18
    jl x_loop_check
    inc r12d
    cmp r12d, 25
    jl y_loop_check
    jmp end_check

horizontal_match_found:
    mov eax, 1
    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    call SetGrid
    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    add edx, 1
    call SetGrid
    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    add edx, 2
    call SetGrid
    add DWORD PTR [rip + score], 1
    jmp next_iteration

vertical_match_found:
    mov eax, 1
    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    call SetGrid
    mov edi, -1
    mov esi, r12d
    add esi, 1
    mov edx, r13d
    call SetGrid
    mov edi, -1
    mov esi, r12d
    add esi, 2
    mov edx, r13d
    call SetGrid
    add DWORD PTR [rip + score], 1
    jmp next_iteration

diagonal_dr_match_found:
    mov eax, 1
    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    call SetGrid
    mov edi, -1
    mov esi, r12d
    add esi, 1
    mov edx, r13d
    add edx, 1
    call SetGrid
    mov edi, -1
    mov esi, r12d
    add esi, 2
    mov edx, r13d
    add edx, 2
    call SetGrid
    add DWORD PTR [rip + score], 1
    jmp next_iteration

diagonal_dl_match_found:
    mov eax, 1
    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    call SetGrid
    mov edi, -1
    mov esi, r12d
    add esi, 1
    mov edx, r13d
    sub edx, 1
    call SetGrid
    mov edi, -1
    mov esi, r12d
    add esi, 2
    mov edx, r13d
    sub edx, 2
    call SetGrid
    add DWORD PTR [rip + score], 1
    jmp next_iteration

end_check:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    mov rsp, rbp
    pop rbp
    ret

CheckMoveDown:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    
    mov r12d, 23
y_loop_move:
    mov r13d, 0
x_loop_move:
    mov edi, r12d
    add edi, 1
    mov esi, r13d
    call GetGrid
    mov r14d, eax

    cmp r14d, -1
    jne next_cell

    mov edi, r12d
    mov esi, r13d
    call GetGrid
    mov r15d, eax

    cmp r15d, -1
    je next_cell

    mov edi, r15d
    mov esi, r12d
    add esi, 1
    mov edx, r13d
    call SetGrid

    mov edi, -1
    mov esi, r12d
    mov edx, r13d
    call SetGrid

next_cell:
    inc r13d
    cmp r13d, 18
    jl x_loop_move

    dec r12d
    cmp r12d, 0
    jge y_loop_move

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.section .note.GNU-stack,"",@progbits



