from setuptools import setup

setup(
    data_files=[
        ("share/zsh/site-functions", ["openfoam/_openfoam"]),
        ("share/bash-completion/completions", ["completions/bash/openfoam"]),
    ],
)
