rule calc_coverage_evenness_two:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        metrics=MDIR + "{sample}/align/{alnr}/alignqc/coverage_evenness_two/{sample}.{alnr}.coverage_evenness_two.tsv",
    conda:
        "../envs/coverage_evenness_two.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.coverage_evenness_two.bench.tsv"
    threads: config['calc_coverage_evenness_two']['threads']
    resources:
        vcpu=config['calc_coverage_evenness_two']['threads'],
        partition=config['calc_coverage_evenness_two']['partition'],
    log:
        MDIR + "{sample}/align/{alnr}/alignqc/coverage_evenness_two/logs/coverage_evenness_two.log",
    params:
        window=config['calc_coverage_evenness_two'].get('window', 100000),
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail;
        mkdir -p $(dirname {output.metrics}) $(dirname {log});
        samtools depth -a {input.cram} 2> {log} | \
        awk -v W={params.window} '
        BEGIN{{
            OFS="\t";
            print "chrom","start","end","mean","median","stdev","cv","evenness","pct_gt_0.2xmean","pct_gt_0.5xmean"
        }}
        function process(chrom,start,count,    i,sum,sumsq,mean,median,sd,cv,even,thr20,thr50,gt20,gt50,sorted,end,pct20,pct50){{
            if(count==0) return;
            sum=0;
            for(i=0;i<count;i++) sum+=depths[i];
            mean=sum/count;
            asort(depths,sorted);
            if(count%2){{median=sorted[(count+1)/2];}} else {{median=(sorted[count/2]+sorted[count/2+1])/2;}}
            sumsq=0;
            for(i=0;i<count;i++) sumsq+=(depths[i]-mean)^2;
            sd=sqrt(sumsq/count);
            cv=(mean>0)?sd/mean:0;
            even=exp(-cv);
            thr20=0.2*mean;
            thr50=0.5*mean;
            gt20=gt50=0;
            for(i=0;i<count;i++){{if(depths[i]>=thr20) gt20++; if(depths[i]>=thr50) gt50++;}}
            pct20=gt20/count*100;
            pct50=gt50/count*100;
            end=start+count;
            printf "%s\t%d\t%d\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.2f\t%.2f\n", chrom,start,end,mean,median,sd,cv,even,pct20,pct50;
        }}
        {{
            chrom=$1; pos=$2; depth=$3;
            if(cchrom==""){{cchrom=chrom; start=pos;}}
            if(chrom!=cchrom || count>=W){{
                process(cchrom,start,count);
                for(i in depths) delete depths[i];
                count=0;
                cchrom=chrom;
                start=pos;
            }}
            depths[count]=depth;
            count++;
        }}
        END{{process(cchrom,start,count);}}
        ' > {output.metrics};
        {latency_wait};
        ls {output.metrics};
        """

localrules: 
    produce_coverage_evenness_two,

rule produce_coverage_evenness_two:  # TARGET: Produce cov eveness TWO.
    input:
            expand(MDIR + "{sample}/align/{alnr}/alignqc/coverage_evenness_two/{sample}.{alnr}.coverage_evenness_two.tsv", sample=SSAMPS, alnr=ALL_ALIGNERS)
    container: None
    threads: 8
    output:
        mqc=MDIR+"other_reports/coverage_evenness_two_combo_mqc.tsv",
    shell:
        """
        mkdir -p $(dirname {output});
        single_file=$( find results | grep coverage_evenness_two.tsv | head -n 1);
        if [[ "$single_file" == "" ]]; then
            echo "NO DATA FOUND" > {output.mqc};
        else
            head -n 1 $single_file > {output.mqc};
            find results | grep .coverage_evenness_two.tsv | parallel -j 1 'tail -n +2 {{}} >> {output.mqc}';
        fi;
        {latency_wait};
        ls {input};
        """