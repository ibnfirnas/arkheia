#! /usr/bin/env zsh

#LIST_NAME='erlang-questions'
LIST_NAME='riak-users'

DATA_DIR='data'
ARCHIVE_DIR="$DATA_DIR/lists/$LIST_NAME/archive"


main() {
    for file in `ls -1 $ARCHIVE_DIR/*.gz`;
    do
        echo $file
        time ./bin/arkheia_old \
            -data-dir $DATA_DIR \
            -list-name $LIST_NAME \
            -mbox-file $file \
            -operation build_index
        echo
    done
}


main
