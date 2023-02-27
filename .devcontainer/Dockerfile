FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
        lua5.3 \
        vim


# ==============================================================================
# -- Convenience
# ==============================================================================

# Bash:
RUN echo "set -o vi" >> ~/.bashrc

# Vim:
RUN echo "nnoremap ss :w<cr>" >> ~/.vimrc