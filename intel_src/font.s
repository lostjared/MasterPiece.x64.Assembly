.intel_syntax noprefix
.section .data
    font_name: .asciz "font.ttf"
    font_error: .asciz "Error loading font"
    render_error: .asciz "Render Text Failed"
    font_loaded: .asciz "Font loaded."
.section .bss
    .lcomm font_ptr, 8
    .comm color_r, 1
    .comm color_g, 1
    .comm color_b, 1
    .comm color_a, 1
    .globl color_r
    .globl color_g
    .globl color_b
    .globl color_a

.section .text
    .extern TTF_Init
    .extern TTF_Quit
    .extern TTF_RenderText_Solid
    .extern SDL_CreateTextureFromSurface
    .extern SDL_FreeSurface
    .extern SDL_DestroyTexture
    .extern exit
    .global printtext
    .global init_text
    .global quit_text
 # edi font size
init_text:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    mov DWORD PTR [rbp - 4], edi
    call TTF_Init
    mov esi, DWORD PTR [rbp - 4]
    lea rdi, [rip + font_name]
    call TTF_OpenFont
    mov [rip + font_ptr], rax
    cmp rax, 0
    je error_init_exit
    lea rdi, [rip + font_loaded]
    call puts
    mov BYTE PTR [rip + color_r], 255
    mov BYTE PTR [rip + color_g], 255
    mov BYTE PTR [rip + color_b], 255
    mov rsp, rbp
    pop rbp
    ret
error_init_exit:
    lea rdi, [rip + font_error]
    call puts
    mov rdi, 1
    call exit
    ret

quit_text:
    push rbp
    mov rbp, rsp
    mov rdi, QWORD PTR [rip + font_ptr]
    call TTF_CloseFont
    call TTF_Quit
    mov rsp, rbp
    pop rbp
    ret

 #rdi, renderer
 #rsi, string
 #edx, x
 #ecx, y
printtext:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x40

    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov r15d, ecx

    mov al, BYTE PTR [rip + color_r]
    mov [rsp + 28], al
    mov al, BYTE PTR [rip + color_g]
    mov [rsp + 29], al
    mov al, BYTE PTR [rip + color_b]
    mov [rsp + 30], al
    mov al, 255
    mov [rsp + 31], al

    mov rdi, QWORD PTR [rip + font_ptr]
    mov rsi, r13
    mov edx, DWORD PTR [rsp + 28]
    call TTF_RenderText_Solid
    mov r13, rax
    cmp rax, 0
    je render_fail

    mov rdi, r12
    mov rsi, r13
    call SDL_CreateTextureFromSurface
    mov r12, rax
    cmp rax, 0
    je render_fail

    mov [rsp + 0], r14d
    mov [rsp + 4], r15d
    mov eax, DWORD PTR [r13 + 16]
    mov [rsp + 8], eax
    mov eax, DWORD PTR [r13 + 20]
    mov [rsp + 12], eax

    mov rdi, r13
    call SDL_FreeSurface

    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov rsi, r12
    mov rdx, 0 # srcrect = NULL
    lea rcx, [rsp + 0] # &dstrect
    call SDL_RenderCopy

    mov rdi, r12
    call SDL_DestroyTexture
    add rsp, 0x40
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsp, rbp
    pop rbp
    ret

render_fail:
    lea rdi, [rip + render_error]
    call puts
    mov rdi, 1
    call exit



.section .note.GNU-stack, "",@progbits

