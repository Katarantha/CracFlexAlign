/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
def valid_params = [
    aligners    : ['star', 'hisat2', 'bowtie2']
]

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowCracflexalign.initialise(params, log)

// TODO nf-core: Add all file path parameters for the pipeline to the list below
// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.fasta ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config          = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config   = params.multiqc_config ? Channel.fromPath( params.multiqc_config, checkIfExists: true ) : Channel.empty()
ch_multiqc_logo            = params.multiqc_logo   ? Channel.fromPath( params.multiqc_logo, checkIfExists: true ) : Channel.empty()
ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK             } from '../subworkflows/local/input_check'
include { BARCODE_LIST_GENERATE   } from '../subworkflows/local/barcode_list_generate'
include { FLEXBAR                 } from '../modules/local/flexbar'
include { PYBARCODEFILTER         } from '../modules/local/pybarcodefilter'
include { PYFASTQDUPLICATEREMOVER } from '../modules/local/pyfastqduplicateremover'
include { PYREADCOUNTERS          } from '../modules/local/pyreadcounters/pyreadcounters'
include { SECONDPYREADCOUNTERS    } from '../modules/local/pyreadcounters/secondpyreadcounters'
include { PYGTF2SGR               } from '../modules/local/pygtf2sgr'
include { PYGTF2BEDGRAPH          } from '../modules/local/pygtf2bedgraph'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { FASTQC                      } from '../modules/nf-core/fastqc/main'
include { MULTIQC                     } from '../modules/nf-core/multiqc/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/custom/dumpsoftwareversions/main'
include { STAR_GENOMEGENERATE         } from '../modules/nf-core/star/genomegenerate/main'
include { STAR_ALIGN                  } from '../modules/nf-core/star/align/main'     
include { HISAT2_BUILD                } from '../modules/nf-core/hisat2/build/main'
include { HISAT2_ALIGN                } from '../modules/nf-core/hisat2/align/main'
include { BOWTIE2_BUILD               } from '../modules/nf-core/bowtie2/build/main'
include { BOWTIE2_ALIGN               } from '../modules/nf-core/bowtie2/align/main'  

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []

workflow CRACFLEXALIGN {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK (
        ch_input
    )
    ch_versions = ch_versions.mix(INPUT_CHECK.out.versions)

    //
    // SUWORKFLOW: parse Samplesheet and generate a barcode.list file 
    //
    BARCODE_LIST_GENERATE (
        ch_input
    )

    //
    // MODULE: Run FastQC
    //

    FASTQC (
        INPUT_CHECK.out.reads
    )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    FLEXBAR ( 
        INPUT_CHECK.out.reads
    ) 
    // ch_versions = ch_versions.mix(FLEXBAR.out.versions.first())

    PYBARCODEFILTER (
        BARCODE_LIST_GENERATE.out.barcodes, FLEXBAR.out.trimmed
    )
    // ch_versions = ch_versions.mix(PYBARCODEFILTER.out.versions.first())

    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: MultiQC
    //

    workflow_summary    = WorkflowCracflexalign.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    methods_description    = WorkflowCracflexalign.methodsDescriptionText(workflow, ch_multiqc_custom_methods_description)
    ch_methods_description = Channel.value(methods_description)

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )
    multiqc_report = MULTIQC.out.report.toList()

//     if (params.aligner == 'star'){
//         indexed_files_ch = STAR_GENOMEGENERATE( genome_ch, gtf_ch)
//     }

//     if (params.aligner == 'hisat2'){
//         indexed_files_ch = HISAT2_BUILD( genome_ch )
//     }

//     if (params.aligner == 'bowtie2'){
//         indexed_files_ch = BOWTIE2_BUILD( genome_ch )
//     }
   
//     //run pyBarcodeFilter with flexbar trimmed reads and barcode sequences

//     demultiplex_ch = PYBARCODEFILTER( flexbar_ch, barcodes_ch )

//     //Collapse the demultiplexed files to remove duplicates using pyFastqDuplicateRemover, flatten the outputs of demultiplexing to stage the inputs as seven seperate files

//     collapse_input_ch = demultiplex_ch.flatten()

//     collapse_ch = PYFASTQDUPLICATEREMOVER( collapse_input_ch )

//     //align the processed reads to the pregenerated Novoindex using Novoalign

//     if (params.aligner == 'star'){
//         align_ch = STAR_ALIGN( indexed_files_ch, collapse_ch)
//     }

//     if (params.aligner == 'hisat2'){
//         align_ch = HISAT2_ALIGN( indexed_files_ch, collapse_ch)
//     }

//     if (params.aligner == 'bowtie2'){
//         align_ch = BOWTIE2_ALIGN( indexed_files_ch, collapse_ch)
//     }
//     //generation of hit tables with pyReadCounters.py from the aligned reads

//     if (params.aligner == 'star'){

//         PYREADCOUNTERS(gtf_ch, align_ch)

//         mapped_ch = SECONDPYREADCOUNTERS(gtf_ch, align_ch)
//     }

//     if (params.aligner == 'hisat2'){

//         PYREADCOUNTERS(gtf_ch, align_ch)

//         mapped_ch = SECONDPYREADCOUNTERS(gtf_ch, align_ch)
//     }

//     if (params.aligner == 'bowtie2'){

//         PYREADCOUNTERS(gtf_ch, align_ch)

//         mapped_ch = SECONDPYREADCOUNTERS(gtf_ch, align_ch)
//     }



//     //generation of chromosome files for usage by the subsequent steps

//     chromosome_ch = CHROMOSOMELENGTH( genome_ch )

//     //generation of a readable coverage file using pyGTF2sgr.py

//     PYGTF2SGR( chromosome_ch, mapped_ch )

//     //generation of readable bedgraph file using pyGTF2bedgraph.py

//     PYGTF2BEDGRAPH( chromosome_ch, mapped_ch )

}



/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
    if (params.hook_url) {
        NfcoreTemplate.IM_notification(workflow, params, summary_params, projectDir, log)
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
