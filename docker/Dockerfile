FROM continuumio/miniconda3

SHELL ["/bin/bash", "-c"]

RUN conda update -n base -c defaults conda
RUN conda create --name ci python=3.8 sphinx sphinx_rtd_theme pip 
RUN conda init bash 
RUN source /opt/conda/etc/profile.d/conda.sh
ENV PATH /opt/conda/envs/ci/bin:$PATH
RUN pip install sphinxcontrib-moderncmakedomain
RUN apt-get update
RUN apt-get install -y make rsync
