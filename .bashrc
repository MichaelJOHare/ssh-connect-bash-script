eval "$(fnm env --use-on-cd --shell bash)"
bind 'set bell-style none'  # causes flickering

alias telnet='/c/msys64/usr/bin/telnet.exe'

# vvv this doesn't seem to do anything anymore...? so confused why EVE was broken before but now works fine
#        - i think it was actually fixed by sourcing bashrc in bash_profile?

#     maybe put this in a different bashrc file and use --rcfile option in profile commandline
#     avoids having to hardcode guid here 
#       - but then wouldn't be able to do vmsmenu in normal bash shell
#           - could maybe alias vmsmenu?
#
# fix CR/LF for OpenVMS only when a real TTY is present and running under VMSMENU profile
#if tty -s && [[ "${WT_PROFILE_ID:-}" == "{69e78f2b-2416-4c8d-bd47-ca33acbbfc29}" ]]; then
    #stty -onlcr
#fi

# load functions
if [[ $- == *i* ]]; then
  [ -r "$HOME/.bash_functions" ] && source "$HOME/.bash_functions"
fi

# custom prompt
PS1='\[\033]0;$PWD\007\]'      # set window title
PS1="$PS1"'\n'                 # new line
PS1="$PS1"'\[\033[32m\]'       # change to green
PS1="$PS1"'mike '              # changed to my name, was: user@host<space>
PS1="$PS1"'\[\033[35m\]'       # change to purple
PS1="$PS1"'\s '                # changed to active shell, was: show MSYSTEM
PS1="$PS1"'\[\033[33m\]'       # change to brownish yellow
PS1="$PS1"'\w'                 # current working directory
PS1="$PS1"'\[\033[0m\]'        # change color
PS1="$PS1"'\n'                 # new line
PS1="$PS1"'$ '                 # prompt: always $