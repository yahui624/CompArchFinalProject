#include "bfs_gpu.cuh"

using namespace std;

#define N 16


__global__
void initializeDeviceArray(int n, int *d_arr, int value, int start_index) {
	const int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid == start_index) {
		d_arr[start_index] = 0;
	}
	else if (tid < n) {
		d_arr[tid] = value;
	}
}


__global__
void printDeviceArray(int *d_arr, int n) {
	const int tid = blockIdx.x * blockDim.x + threadIdx.x;
	if (tid < n) {
		printf("d_arr[%i] = %i \n", tid, d_arr[tid]);
	}
}


/*
 * Given a graph and a current queue computes next vertices (vertex frontiers) to traverse.
 */
__global__
void computeNextQueue(int *adjacencyList, int *edgesOffset, int *edgesSize, int *distance,
		int queueSize, int *currentQueue, int *nextQueueSize, int *nextQueue, int level) {
	int tid = blockIdx.x * blockDim.x + threadIdx.x;  // thread id
	if (tid < queueSize) {  // visit all vertexes in a queue in parallel
		int current = currentQueue[tid];
		for (int i = edgesOffset[current]; i < edgesOffset[current] + edgesSize[current]; ++i) {
			printf("tid %i: i = %i \n", tid, i);
			int v = adjacencyList[i];
			printf("tid %i: Currently considering vertex %i. distance = %i \n", tid, v, distance[v]);
			if (distance[v] == INT_MAX) {
				distance[v] = level + 1;
				int position = atomicAdd(nextQueueSize, 1);
				printf("Adding %i to the position %i of the queue \n", v, position);
				nextQueue[position] = v;
			}
		}
	}
}


void bfsGPU(int start, Graph &G, vector<int> &distance, vector<bool> &visited) {

	// Initialization of GPU variables
	int *d_adjacencyList;
	int *d_edgesOffset;
	int *d_edgesSize;
	int *d_firstQueue;
	int *d_secondQueue;
	int *d_nextQueueSize;
	int *d_distance; // output

	// Initialization of CPU variables
	int currentQueueSize = 1;
	const int nextQueueSize = 0;
	int level = 0;

	// Allocation on device
	const int size = G.numVertices * sizeof(int);
	const int adjacencySize = G.adjacencyList.size() * sizeof(int);
	cudaMalloc((void **)&d_adjacencyList, adjacencySize);
	cudaMalloc((void **)&d_edgesOffset, size);
	cudaMalloc((void **)&d_edgesSize, size);
	cudaMalloc((void **)&d_firstQueue, size);
	cudaMalloc((void **)&d_secondQueue, size);
	cudaMalloc((void **)&d_distance, size);
	cudaMalloc((void **)&d_nextQueueSize, sizeof(int));

	// Copy inputs to device
	cudaMemcpy(d_adjacencyList, &G.adjacencyList[0], adjacencySize, cudaMemcpyHostToDevice);
	cudaMemcpy(d_edgesOffset, &G.edgesOffset[0], size, cudaMemcpyHostToDevice);
	cudaMemcpy(d_edgesSize, &G.edgesSize[0], size, cudaMemcpyHostToDevice);
	cudaMemcpy(d_nextQueueSize, &nextQueueSize, sizeof(int), cudaMemcpyHostToDevice);
	//change_elem<<<1, 1>>> (d_firstQueue, 0, start);
	cudaMemcpy(d_firstQueue, &start, sizeof(int), cudaMemcpyHostToDevice);
	// d_distance
	initializeDeviceArray<<<N, 1>>> (G.numVertices, d_distance, INT_MAX, start);
	cudaDeviceSynchronize();

	while (currentQueueSize > 0) {
		int *d_currentQueue;
		int *d_nextQueue;
		if (level % 2 == 0) {
			d_currentQueue = d_firstQueue;
			d_nextQueue = d_secondQueue;
		}
		else {
			d_currentQueue = d_secondQueue;
			d_nextQueue = d_firstQueue;
		}
		computeNextQueue<<<N, 1>>> (d_adjacencyList, d_edgesOffset, d_edgesSize, d_distance,
				currentQueueSize, d_currentQueue, d_nextQueueSize, d_nextQueue, level);
		cudaDeviceSynchronize();
		++level;
		cudaMemcpy(&currentQueueSize, d_nextQueueSize, sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(d_nextQueueSize, &nextQueueSize, sizeof(int), cudaMemcpyHostToDevice);
//		cout << "End of loop on the host, currentQueueSize: " << currentQueueSize << endl;
	}

	cudaMemcpy(&distance[0], d_distance, size, cudaMemcpyDeviceToHost);

	// Cleanup
	cudaFree(d_adjacencyList);
	cudaFree(d_edgesOffset);
	cudaFree(d_edgesSize);
	cudaFree(d_firstQueue);
	cudaFree(d_secondQueue);
}
