#!/bin/bash

# fail whenever something is fishy, use -x to get verbose logfiles
set -e -u -x

ds_path=$(realpath $(dirname $0)/..)
sub=$1
# $TMPDIR is a more performant local filesystem
wrkDir=$TMPDIR/$LSB_JOBID
mkdir -p $wrkDir
cd $wrkDir
# get the output/input datasets
# flock makes sure that this does not interfere with another job
# finishing at the same time, and pushing its results back
# we clone from the location that we want to push the results too
flock $DSLOCKFILE datalad clone $ds_path ds
# all following actions are performed in the context of the superdataset
cd ds
# obtain datasets
datalad get -r nifti/sub-${sub}
datalad get -r mimosa/sub-${sub}
datalad get simg/mimosa_0.1.0.sif
# let git-annex know that we do not want to remember any of these clones
# (we could have used an --ephemeral clone, but that might deposite data
# of failed jobs at the origin location, if the job runs on a shared
# filesystem -- let's stay self-contained)
git submodule foreach --recursive git annex dead here

# checkout new branches
# this enables us to store the results of this job, and push them back
# without interference from other jobs
git -C mimosa/sub-$sub checkout -b "sub-${sub}"

export SINGULARITYENV_LSB_DJOB_NUMPROC=$LSB_DJOB_NUMPROC
export SINGULARITYENV_NSLOTS=$LSB_DJOB_NUMPROC
export SINGULARITYENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$LSB_DJOB_NUMPROC
export SINGULARITYENV_ANTS_RANDOM_SEED=123
# yay time to run
for ses in 3T 3T0 3T1 64mT; do
    mkdir -p $PWD/mimosa/sub-${sub}/ses-${ses}
    if [ ! -e $PWD/mimosa/sub-${sub}/ses-${ses}/mimosa_binary_mask_0.2.nii.gz ]; then
        if [ $ses = "64mT" ]; then
            # same as below, but not N4
            datalad run -i nifti/sub-$sub -i simg/mimosa_0.1.0.sif -o mimosa/sub-$sub/ses-${ses} --explicit \
                singularity run --cleanenv \
                -B /project -B $TMPDIR -B $TMPDIR:/tmp \
                $PWD/simg/mimosa_0.1.0.sif \
                $PWD/nifti $PWD/mimosa/sub-${sub}/ses-${ses} participant --participant_label $sub --session $ses --strip mass --register --whitestripe --debug --skip_bids_validator
        else
            datalad run -i nifti/sub-$sub -i simg/mimosa_0.1.0.sif -o mimosa/sub-$sub/ses-${ses} --explicit \
                singularity run --cleanenv \
                -B /project -B $TMPDIR -B $TMPDIR:/tmp \
                $PWD/simg/mimosa_0.1.0.sif \
                $PWD/nifti $PWD/mimosa/sub-${sub}/ses-${ses} participant --participant_label $sub --session $ses --strip mass --n4 --register --whitestripe --debug --skip_bids_validator
        fi
    fi
done

# selectively push outputs only
# ignore root dataset, despite recorded changes, needs coordinated
# merge at receiving end
flock $DSLOCKFILE datalad push -d mimosa/sub-${sub} --to origin

cd ../..
chmod -R 777 $wrkDir
rm -rf $wrkDir
