// Copyright www.computing.llnl.gov
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <limits.h>
#include <omp.h>
#include <assert.h>
#include <time.h>

__device__ int minDistance(long dist[], bool sptSet[], long V)
{
    // Initialize min value
    int min = INT_MAX, min_index;

    for (int v = 0; v < V; v++)
    {
        if ((sptSet[v] == false) && (dist[v] <= min))
        {
            min = dist[v], min_index = v;
        }
    }

    return min_index;
}

__device__ void dijkstra(long src, long V, long *graph, long *dist)
{
    // sptSet[i] will be true if vertex i is included in shortest path tree or shortest distance from src to i is finalized
    bool *sptSet = (bool*)malloc(V);

    // Initialize all distances as INFINITE and stpSet[] as false
    for (int i = 0; i < V; i++)
    {
        dist[i] = INT_MAX, sptSet[i] = false;
    }

    // Distance of source vertex from itself is always 0
    dist[src] = 0;

    // Find shortest path for all vertices
    for (int count = 0; count < V - 1; count++)
    {
        // Pick the minimum distance vertex from the set of vertices not yet processed. u is always equal to src in the first iteration.
        int u = minDistance(dist, sptSet, V);

        // Mark the picked vertex as processed
        sptSet[u] = true;

        // Update dist value of the adjacent vertices of the picked vertex.
        for (int v = 0; v < V; v++)
        {
            // Update dist[v] only if is not in sptSet, there is an edge from u to v, and total weight of path from src to  v through u is smaller than current value of dist[v]
            if (!sptSet[v] && graph[(u * V) + v] && (dist[u] != INT_MAX) && (dist[u] + graph[(u * V) + v] < dist[v]))
            {
                dist[v] = dist[u] + graph[(u * V) + v];
            }
        }
    }
}

__global__ void solution(long *matrix, long *newmatrix, long nodes) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    long *dist = (long*)malloc(nodes);
    for (int i = index; i < nodes; i += stride)
    {
        dijkstra(i, nodes, matrix, dist);
        // printf("Completing part %d with processor %d\n", i, rank);
        // MPI_Send(newmatrix[i], nodes, MPI_INT, 0, i, MPI_COMM_WORLD);
        memcpy(&newmatrix[i*nodes], dist, nodes*sizeof(*dist));
    }

}

int main(int argc, char *argv[])
{
    // Set rand() seed
    srand(13517020);
    /* total cost == 0
     size | total
     100  |    0
     500  |    4
     1000 |   18
     3000 |  135
     5000 |  380
	*/
    // srand(13517137);
    /* total cost == 0
     size | total
     100  |    0
     500  |    2
     1000 |   13
     3000 |  126
     5000 |  360
  	*/

    if (argc < 2)
    {
        fprintf(stderr, "error: missing command line arguments\n");
        exit(1);
    }
    else
    {
        clock_t begin = clock();
        // Inititate graph
        long nodes = atoi(argv[1]);
        long num_bytes = nodes*nodes*sizeof(long);
        long *d_matrix, *h_matrix = 0;

        h_matrix = (long*)malloc(num_bytes);
        cudaMalloc((void**)&d_matrix, num_bytes);

        if (0==h_matrix || 0==d_matrix) {
            printf("Couldn't allocate memory\n");
            return 1;
        }

        cudaMemset(d_matrix,0,num_bytes);
        
        // Build graph
        for (int i = 0; i < nodes; i++)
        {
            for (int j = 0; j < nodes; j++)
            {
                if (i == j)
                {
                    h_matrix[(i*nodes) + j] = 0;
                }
                else
                {
                    h_matrix[(i*nodes) + j] = rand();
                }
            }
        }

        cudaMemcpy(d_matrix,h_matrix,num_bytes,cudaMemcpyHostToDevice);
        
        long *d_newMatrix, *h_newMatrix = 0;

        h_newMatrix = (long*)malloc(num_bytes);
        cudaMalloc((void**)&d_newMatrix, num_bytes);

        if (0==h_newMatrix || 0==d_newMatrix) {
            printf("Couldn't allocate newmatrix memory\n");
            return 1;
        }

        cudaMemset(d_newMatrix,0,num_bytes);

        int blockSize = 256;
        int numBlocks = (nodes + blockSize - 1) / blockSize;
        solution<<<numBlocks, blockSize>>>(d_matrix, d_newMatrix, nodes);

        cudaMemcpy( h_newMatrix, d_newMatrix, num_bytes, cudaMemcpyDeviceToHost );

        clock_t end = clock();
        // printf("Printing to file");
        // Write to file
        FILE *fp;
        fp = fopen("old_matrix.txt", "w");
        fprintf(fp, "Old matrix:\n");

        for (int i = 0; i < nodes; i++)
        {
            for (int j = 0; j < nodes; j++)
            {
                fprintf(fp, "%ld ", h_matrix[(i*nodes) +j]);
            }

            fprintf(fp, "\n");
        }

        fclose(fp);

        fp = fopen("result.txt", "w");
        fprintf(fp, "New matrix:\n");

        for (int i = 0; i < nodes; i++)
        {
            for (int j = 0; j < nodes; j++)
            {
                fprintf(fp, "%ld ", h_newMatrix[(i*nodes) + j]);
            }

            fprintf(fp, "\n");
        }

        fprintf(fp, "Solution found in: %.3f microseconds\n", ((double)(end - begin) / CLOCKS_PER_SEC) * 1000000);
        printf("Solution found in: %.3f microseconds\n", ((double)(end - begin) / CLOCKS_PER_SEC) * 1000000);
        fclose(fp);

        // Dealocation

        free(h_matrix);
        free(h_newMatrix);
        cudaFree(d_matrix);
        cudaFree(d_newMatrix);
    }
    return 0;
}