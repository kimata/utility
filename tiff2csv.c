// gcc -std=c99 -ltiff -o tiff2csv tiff2csv.c

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <tiffio.h>
#include <string.h>

#define CSV_EXT ".csv"

typedef struct {
    uint8_t *raster;
    uint32_t width;
    uint32_t height;
    uint32_t bps;
    uint32_t spp;
    uint32_t plan;
} tiff_image_t;

uint32_t *read_tiff(char *file_path, tiff_image_t *image)
{
    TIFF *tiff;
    if ((tiff = TIFFOpen(file_path, "r")) == NULL) {
        fprintf(stderr, "Could not open %s\n", file_path);
        exit(EXIT_FAILURE);
    }

    TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH, &(image->width));
    TIFFGetField(tiff, TIFFTAG_IMAGELENGTH, &(image->height));
    TIFFGetField(tiff, TIFFTAG_BITSPERSAMPLE, &(image->bps));
    TIFFGetField(tiff, TIFFTAG_SAMPLESPERPIXEL, &(image->spp));
    TIFFGetField(tiff, TIFFTAG_PLANARCONFIG, &(image->plan));

    if (image->plan != PLANARCONFIG_CONTIG) {
        fprintf(stderr, "Not support TIFFTAG_PLANARCONFIG=%d\n", image->plan);
        exit(EXIT_FAILURE);
    }
    uint32_t line_size = TIFFScanlineSize(tiff);
    image->raster = malloc(line_size * image->height);
    if (image->raster == NULL) {
        fprintf(stderr, "Could not allocate enough memory\n");
        exit(EXIT_FAILURE);
    }

    for (uint32_t y = 0; y < image->height; y++) {
        TIFFReadScanline(tiff, &(image->raster[line_size * y]), y, 0);
    }
    TIFFClose(tiff);

    return 0;
}

void convert_tiff(char *file_path, tiff_image_t *image)
{
    FILE *file = fopen(file_path,"w");
    if (file == NULL) {
        fprintf(stderr, "Could not open %s\n", file_path);
        exit(EXIT_FAILURE);
    }
    uint16_t color;
    for (uint32_t c = 0; c < image->spp; c++) {
        for(uint32_t y = image->height-1; y != -1; y--) {
            for (uint32_t x = 0; x < image->width; x++) {
                color = ((uint16 *)image->raster)[(y*image->width + x) * image->spp + c];
                fprintf(file, "%d,", color);
            }
            fprintf(file, "\n");
        }
        fprintf(file, "\n\n\n\n");
    }
    fclose(file);
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s FILE\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    char *tiff_file_path = argv[1];
    char *csv_file_path = malloc(strlen(tiff_file_path + strlen(CSV_EXT) + 1));
    strcpy(csv_file_path, tiff_file_path);
    strcat(csv_file_path, CSV_EXT);

    tiff_image_t image;
    memset(&image, 0, sizeof(image));

    read_tiff(tiff_file_path, &image);

    printf("convert %s -> %s size=%dx%d %dbit(%d)\n",
           tiff_file_path, csv_file_path,
           image.width, image.height, image.bps, image.spp);

    convert_tiff(csv_file_path, &image);
}
