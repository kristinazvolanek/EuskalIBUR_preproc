#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses run TEs wdr"
echo "Optional:"
echo "anatsfx asegsfx voldiscard sbref slicetimeinterp despike fwhm scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anatsfx=none
asegsfx=none
voldiscard=10
slicetimeinterp=no
sbref=default
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/02.func_preproc
debug=no
fwhm=none

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-run)		run=$2;shift;;
		-TEs)		TEs="$2";shift;;
		-wdr)		wdr=$2;shift;;

		-anatsfx)			anatsfx=$2;shift;;
		-asegsfx)			asegsfx=$2;shift;;
		-voldiscard)		voldiscard=$2;shift;;
		-sbref)				sbref=$2;shift;;
		-fwhm)				fwhm=$2;shift;;
		-slicetimeinterp)	slicetimeinterp=yes;;
		-despike)			despike=yes;;
		-scriptdir)			scriptdir=$2;shift;;
		-tmp)				tmp=$2;shift;;
		-debug)				debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses run TEs wdr
scriptdir=${scriptdir%/}
[[ ${sbref} == "default " ]] && sbref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
[[ ${mask} == "default " ]] && mask=${sbref}_brain_mask
checkoptvar anatsfx asegsfx voldiscard sbref slicetimeinterp despike scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anatsfx asegsfx
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
aTEs=( ${TEs} )
nTE=${#aTEs[@]}
fileprx=sub-${sub}_ses-${ses}
[[ ${anatsfx} != "none" ]] && anat=${wdr}/sub-${sub}/ses-${ses}/anat/${fileprx}_${anatsfx} || anat=none
[[ ${asegsfx} != "none" ]] && aseg=${wdr}/sub-${sub}/ses-${ses}/anat/${fileprx}_${asegsfx} || aseg=none
fdir=${wdr}/sub-${sub}/ses-${ses}/func
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}
### Cath errors and exit on them
set -e
######################################
#########    Task preproc    #########
######################################

# Start making the tmp folder
mkdir ${tmp}

for e in $( seq 1 ${nTE} )
do
	echo "************************************"
	echo "*** Func correct rest run ${run} BOLD echo ${e}"
	echo "************************************"
	echo "************************************"

	echo "bold=${fileprx}_task-rest_run-${run}_echo-${e}_bold"
	bold=${fileprx}_task-rest_run-${run}_echo-${e}_bold
	${scriptdir}/01.func_correct.sh -func_in ${bold} -fdir ${fdir} \
									-voldiscard ${voldiscard} \
									-despike ${despike} \
									-slicetimeinterp ${slicetimeinterp} -tmp ${tmp}
done

echo "************************************"
echo "*** Func spacecomp rest run ${run} echo 1"
echo "************************************"
echo "************************************"

echo "fmat=${fileprx}_task-rest_run-${run}_echo-1_bold"
fmat=${fileprx}_task-rest_run-${run}_echo-1_bold

${scriptdir}/03.func_spacecomp.sh -func_in ${fmat}_cr -fdir ${fdir} -anat ${anat} \
								  -mref ${sbref} -aseg ${aseg} -tmp ${tmp}

for e in $( seq 1 ${nTE} )
do
	echo "************************************"
	echo "*** Func realign rest run ${run} BOLD echo ${e}"
	echo "************************************"
	echo "************************************"

	echo "bold=${fileprx}_task-rest_run-${run}_echo-${e}_bold_cr"
	bold=${fileprx}_task-rest_run-${run}_echo-${e}_bold_cr
	${scriptdir}/04.func_realign.sh -func_in ${bold} -fmat ${fmat} -mask ${mask} \
									-fdir ${fdir} -mref ${sbref} -tmp ${tmp}

	echo "************************************"
	echo "*** Func greyplot rest run ${run} BOLD echo ${e} (pre)"
	echo "************************************"
	echo "************************************"
	echo "bold=${fileprx}_task-rest_run-${run}_echo-${e}_bold_bet"
	bold=${fileprx}_task-rest_run-${run}_echo-${e}_bold_bet
	${scriptdir}/12.func_grayplot.sh -func_in ${bold} -fdir ${fdir} -anat ${anat} \
									 -mref ${sbref} -aseg ${aseg} -polort 4 -tmp ${tmp}
done

echo "************************************"
echo "*** Func MEICA rest run ${run} BOLD"
echo "************************************"
echo "************************************"

${scriptdir}/05.func_meica.sh -func_in ${fmat}_bet -fdir ${fdir} -TEs "${TEs}" -tmp ${tmp}

echo "************************************"
echo "*** Func T2smap rest run ${run} BOLD"
echo "************************************"
echo "************************************"
# Since t2smap gives different results from tedana, prefer the former for optcom
${scriptdir}/06.func_optcom.sh -func_in ${fmat}_bet -fdir ${fdir} -TEs "${TEs}" -tmp ${tmp}

# As it's rest_run-${run}, don't skip anything!
# Also repeat everything twice for meica-denoised and not
for e in $( seq 1 ${nTE}; echo "optcom" )
do
	if [ ${e} != "optcom" ]
	then
		e=echo-${e}
	fi
	echo "bold=${fileprx}_task-rest_run-${run}_${e}_bold"
	bold=${fileprx}_task-rest_run-${run}_${e}_bold
	
	echo "************************************"
	echo "*** Func Nuiscomp rest run ${run} BOLD ${e}"
	echo "************************************"
	echo "************************************"

	${scriptdir}/07.func_nuiscomp.sh -func_in ${bold}_bet -fmat ${fmat} \
									 -mref ${sbref} -fdir ${fdir} \
									 -anat ${anat} -aseg ${aseg} -polort 4 \
									 -den_motreg -den_detrend \
									 -applynuisance -tmp ${tmp}
	
	echo "************************************"
	echo "*** Func Pepolar rest run ${run} BOLD ${e}"
	echo "************************************"
	echo "************************************"

	${scriptdir}/02.func_pepolar.sh -func_in ${bold}_den -fdir ${fdir} \
									-pepolar ${sbref}_topup -tmp ${tmp}

	boldout=$( basename ${bold} )
	if [[ ${fwhm} != "none" ]]
	then

		echo "************************************"
		echo "*** Func smoothing rest run ${run} BOLD ${e}"
		echo "************************************"
		echo "************************************"

		${scriptdir}/08.func_smooth.sh -func_in ${bold}_tpp -fdir ${fdir} -fwhm ${fwhm} -mask ${mask} -tmp ${tmp}
		echo "3dcalc -a ${bold}_sm.nii.gz -b ${mask}.nii.gz -expr 'a*b' -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz -short -gscale"
		3dcalc -a ${bold}_sm.nii.gz -b ${mask}.nii.gz -expr 'a*b' -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz -short -gscale
		boldsource=${bold}_sm
	else
		echo "3dcalc -a ${bold}_sm.nii.gz -b ${mask}.nii.gz -expr 'a*b' -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz -short -gscale"
		3dcalc -a ${bold}_sm.nii.gz -b ${mask}.nii.gz -expr 'a*b' -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz -short -gscale
		boldsource=${bold}_tpp
	fi

	echo "************************************"
	echo "*** Func greyplot rest run ${run} BOLD echo ${e} (post)"
	echo "************************************"
	echo "************************************"
	${scriptdir}/12.func_grayplot.sh -func_in ${boldsource} -fdir ${fdir} -anat ${anat} \
									 -mref ${sbref} -aseg ${aseg} -polort 4 -tmp ${tmp}

	echo "mv ${bold}_sm_gp_PVO.png ${fdir}/00.${boldout}_native_preprocessed_gp_PVO.png"
	mv ${bold}_sm_gp_PVO.png ${fdir}/00.${boldout}_native_preprocessed_gp_PVO.png
	echo "mv ${bold}_sm_gp_IJK.png ${fdir}/00.${boldout}_native_preprocessed_gp_IJK.png"
	mv ${bold}_sm_gp_IJK.png ${fdir}/00.${boldout}_native_preprocessed_gp_IJK.png
	echo "mv ${bold}_sm_gp_peel.png ${fdir}/00.${boldout}_native_preprocessed_gp_peel.png"
	mv ${bold}_sm_gp_peel.png ${fdir}/00.${boldout}_native_preprocessed_gp_peel.png

done

[[ ${debug} == "yes" ]] && set +x

exit 0