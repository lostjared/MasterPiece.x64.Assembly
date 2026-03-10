.intel_syntax noprefix
.section .data
    window_title: .asciz "MasterPiece Assembly"
    background_path: .asciz "bg.bmp"
    intro_path: .asciz "intro.bmp"
    error_msg: .asciz "Error loading background image\n"
    open_mode: .asciz "rb"
    format_string: .asciz "Score: %d"
    mouse_x: .asciz "Mouse X,Y: %d %d\n"
    keypress: .asciz "Key pressed %d\n"
.section .bss
    .lcomm window_ptr, 8      
    .lcomm bg_surface, 8
    .lcomm bg_texture, 8
    .lcomm intro_surface, 8
    .lcomm intro_texture, 8
    .comm renderer_ptr, 8    
    .lcomm event_buffer, 128  
    .lcomm text_buffer, 256
    .lcomm game_screen, 8
    .comm score, 4
    .globl renderer_ptr 
    .globl score
    .lcomm last_key_time, 4
.section .text
    .extern SDL_Init
    .extern SDL_CreateWindow
    .extern SDL_CreateRenderer
    .extern SDL_SetRenderDrawColor
    .extern SDL_RenderClear
    .extern SDL_RenderPresent
    .extern SDL_PollEvent
    .extern SDL_DestroyRenderer
    .extern SDL_DestroyWindow
    .extern SDL_Quit
    .extern SDL_Delay
    .extern SDL_RWFromFile
    .extern SDL_LoadBMP_RW
    .extern SDL_DestroyTexture
    .extern SDL_RenderCopy
    .extern puts
    .extern srand
    .extern time
    .extern exit
    .extern DrawBlocks
    .extern MoveLeft
    .extern MoveRight
    .extern MoveDown
    .extern ShiftUp
    .extern CheckGrid
    .extern CheckMoveDown
    .extern init_text
    .extern quit_text
    .extern printtext
    .extern snprintf
    .global main
main:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov rdi, 0
    mov DWORD PTR [rbp + -8], 0
    call time
    mov rdi, rax
    call srand
    mov edi, -1
    call FillGrid
    mov edi, 0x20
    call SDL_Init
    test eax, eax
    jnz exit_error
    lea rdi, [rip + window_title]
    mov esi, 100
    mov edx, 100
    mov ecx, 640
    mov r8d, 480
    mov r9d, 0
    call SDL_CreateWindow
    test rax, rax
    jz cleanup_and_exit
    mov [rip + window_ptr], rax
    mov rdi, QWORD PTR [rip + window_ptr]
    mov esi, -1
    mov edx, 0
    call SDL_CreateRenderer
    test rax, rax
    jz cleanup_window
    mov [rip + renderer_ptr], rax
    call InitBlocks
 #load bg
    lea rdi, [rip + background_path]
    lea rsi, [rip + open_mode]
    call SDL_RWFromFile
    cmp rax, 0
    je error_exit
    mov rdi, rax
    mov esi, 1
    call SDL_LoadBMP_RW
    cmp rax, 0
    je error_exit
    mov [rip + bg_surface], rax
    mov rsi, QWORD PTR [rip + bg_surface]
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call SDL_CreateTextureFromSurface
    cmp rax, 0
    je error_exit
    mov [rip + bg_texture], rax
    mov rdi, QWORD PTR [rip + bg_surface]
    call SDL_FreeSurface
 #load intro
    lea rdi, [rip + intro_path]
    lea rsi, [rip + open_mode]
    call SDL_RWFromFile
    cmp rax, 0
    je error_exit
    mov rdi, rax
    mov esi, 1
    call SDL_LoadBMP_RW
    cmp rax, 0
    je error_exit
    mov [rip + intro_surface], rax
    mov rsi, QWORD PTR [rip + intro_surface]
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call SDL_CreateTextureFromSurface
    cmp rax, 0
    je error_exit
    mov [rip + intro_texture], rax
    mov rdi, QWORD PTR [rip + intro_surface]
    call SDL_FreeSurface
 #init text
    mov edi, 24
    call init_text
 #init screen
    mov QWORD PTR [rip + game_screen], 0
main_loop:
    
.process_events:
    lea rdi, [rip + event_buffer]
    call SDL_PollEvent
    cmp eax, 0
    je render_frame
    mov eax, DWORD PTR [rip + event_buffer]
    cmp eax, 0x100
    je cleanup_all

    mov eax, DWORD PTR [rip + event_buffer+20]
    cmp eax, 13
    je pressed_enter

    mov eax, DWORD PTR [rip + event_buffer+16]
    cmp eax, 0x29
    je cleanup_all

    cmp QWORD PTR [rip + game_screen], 1
    je .skip_mouse
    cmp eax, 0x300
    jne check_mouse
.skip_mouse:
    call SDL_GetTicks
    mov ecx, eax
    mov edx, [rip + last_key_time]
    sub ecx, edx
    cmp ecx, 120
    jb .process_events
    mov [rip + last_key_time], eax
    mov eax, DWORD PTR [rip + event_buffer+20]
    cmp eax, 0x40000050
    je key_left
    cmp eax, 0x4000004F
    je key_right
    cmp eax, 0x40000051
    je key_down
    cmp eax, 0x40000052
    je key_up
    jmp .process_events
check_mouse:
    mov eax, DWORD PTR [rip + event_buffer]
    cmp eax, 0x401
    jne .process_events

    mov eax, DWORD PTR [rip + event_buffer+20]
    cmp eax, 214
    jl .process_events
    cmp eax, 360
    jge .process_events

    mov eax, DWORD PTR [rip + event_buffer+24]
    cmp eax, 336
    jl .process_events
    cmp eax, 393
    jge .process_events
    jmp .clicked
.clicked:
    mov QWORD PTR [rip + game_screen], 1
    jmp .process_events
render_frame:

    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov esi, 0
    mov edx, 0
    mov ecx, 0
    mov r8d, 255
    call SDL_SetRenderDrawColor
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call SDL_RenderClear
    cmp QWORD PTR [rip + game_screen], 0
    je .draw_intro
.draw_game:
    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov rsi, QWORD PTR [rip + bg_texture]
    mov rdx, 0
    mov rcx, 0
    call SDL_RenderCopy
    call CheckGrid
    call CheckMoveDown
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call DrawGrid
    call DrawBlocks
 #draw score
    lea rdi, [rip + text_buffer]
    mov esi, 256
    lea rdx, [rip + format_string]
    mov ecx, DWORD PTR [rip + score]
    xor rax, rax
    call snprintf
    mov rdi, QWORD PTR [rip + renderer_ptr]
    lea rsi, [rip + text_buffer]
    mov edx, 15
    mov ecx, 15
    call printtext
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call SDL_RenderPresent
    call SDL_GetTicks
    mov [rbp + -4], eax
    cmp DWORD PTR [rbp - 8], 0
    je set_last_ticks
    mov edx, [rbp + -8]
    sub eax, edx
    cmp eax, 1200
    jb skip_move_down
    call MoveDown
    call SDL_GetTicks
    mov [rbp + -8], eax
    jmp skip_move_down
set_last_ticks:
    mov eax, [rbp + -4]
    mov [rbp + -8], eax
skip_move_down:
    mov edi, 4
    call SDL_Delay
    jmp main_loop

.draw_intro:
    mov rdi, QWORD PTR [rip + renderer_ptr]
    mov rsi, QWORD PTR [rip + intro_texture]
    mov rdx, 0
    mov rcx, 0
    call SDL_RenderCopy
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call SDL_RenderPresent
    mov edi, 1
    call SDL_Delay
    jmp main_loop
key_left:
    call MoveLeft
    jmp .process_events
key_right:
    call MoveRight
    jmp .process_events
key_down:
    call MoveDown
    jmp .process_events
key_up:
    call ShiftUp
    jmp .process_events
pressed_enter:
    mov QWORD PTR [rip + game_screen], 1
    jmp .process_events
cleanup_all:
    mov rdi, QWORD PTR [rip + intro_texture]
    call SDL_DestroyTexture
    mov rdi, QWORD PTR [rip + bg_texture]
    call SDL_DestroyTexture
    mov rdi, QWORD PTR [rip + renderer_ptr]
    call SDL_DestroyRenderer
cleanup_window:
    mov rdi, QWORD PTR [rip + window_ptr]
    call SDL_DestroyWindow
cleanup_and_exit:
    call quit_text
    call SDL_Quit
    mov edi, 0
    call exit
error_exit:
    lea rdi, [rip + error_msg]
    call puts
exit_error:
    call SDL_Quit
    mov edi, 1
    call exit

.section .note.GNU-stack,"",@progbits


.section .note.GNU-stack, "",@progbits

