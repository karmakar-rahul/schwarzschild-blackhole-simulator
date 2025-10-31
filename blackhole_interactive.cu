
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <GL/glew.h>
#include <GLFW/glfw3.h>
#include <cuda_runtime.h>

#define WIDTH 1600
#define HEIGHT 900
#define MAX_STEPS 2000
#define STEP_SIZE 0.006f
#define SCHWARZSCHILD_RADIUS 3.0f
#define TEXTURE_WIDTH 4096
#define TEXTURE_HEIGHT 4096

// Camera state
struct Camera {
    float distance;
    float theta;
    float phi;
    float rotation_speed;
};

Camera g_camera = {15.0f, 1.2f, 0.0f, 0.4f};
bool g_mouse_pressed = false;
double g_last_x = 0.0, g_last_y = 0.0;

// Vector operations
struct Vec3 {
    float x, y, z;
};

__device__ Vec3 vec3_add(Vec3 a, Vec3 b) {
    return {a.x + b.x, a.y + b.y, a.z + b.z};
}

__device__ Vec3 vec3_sub(Vec3 a, Vec3 b) {
    return {a.x - b.x, a.y - b.y, a.z - b.z};
}

__device__ Vec3 vec3_scale(Vec3 v, float s) {
    return {v.x * s, v.y * s, v.z * s};
}

__device__ float vec3_dot(Vec3 a, Vec3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

__device__ float vec3_length(Vec3 v) {
    return sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
}

__device__ Vec3 vec3_normalize(Vec3 v) {
    float len = vec3_length(v);
    if (len > 1e-6f) {
        return {v.x / len, v.y / len, v.z / len};
    }
    return {0.0f, 0.0f, 1.0f};
}

// Schwarzschild acceleration - STRONGER lensing
__device__ Vec3 compute_acceleration(Vec3 pos, Vec3 vel) {
    float r = vec3_length(pos);
    
    if (r < SCHWARZSCHILD_RADIUS * 1.01f) {
        return {0.0f, 0.0f, 0.0f};
    }
    
    float rs = SCHWARZSCHILD_RADIUS;
    float r2 = r * r;
    float r3 = r2 * r;
    
    Vec3 r_hat = vec3_normalize(pos);
    float v_r = vec3_dot(vel, r_hat);
    
    Vec3 v_tang = vec3_sub(vel, vec3_scale(r_hat, v_r));
    float v_tang2 = vec3_dot(v_tang, v_tang);
    
    // Increase lensing strength by 2.5x
    float factor = -3.75f * rs / r3;
    Vec3 accel = vec3_scale(pos, factor * v_tang2);
    
    return accel;
}

// Sample from background texture using spherical mapping with bilinear filtering
__device__ Vec3 sample_background_texture(Vec3 dir, unsigned char* texture, int tex_width, int tex_height) {
    // Convert direction to spherical coordinates
    float theta = atan2f(dir.z, dir.x);
    float phi = asinf(fmaxf(-1.0f, fminf(1.0f, dir.y))); // Clamp to avoid NaN
    
    // Map to texture coordinates [0, 1]
    float u = (theta + 3.14159265f) / (2.0f * 3.14159265f);
    float v = (phi + 3.14159265f / 2.0f) / 3.14159265f;
    
    // Wrap coordinates
    u = u - floorf(u);
    v = v - floorf(v);
    
    // Get float coordinates
    float fx = u * (tex_width - 1);
    float fy = v * (tex_height - 1);
    
    // Bilinear interpolation
    int x0 = (int)fx;
    int y0 = (int)fy;
    int x1 = (x0 + 1) % tex_width;
    int y1 = (y0 + 1) % tex_height;
    
    float wx = fx - x0;
    float wy = fy - y0;
    
    // Sample 4 neighboring pixels
    int idx00 = (y0 * tex_width + x0) * 3;
    int idx10 = (y0 * tex_width + x1) * 3;
    int idx01 = (y1 * tex_width + x0) * 3;
    int idx11 = (y1 * tex_width + x1) * 3;
    
    Vec3 color;
    // Interpolate red channel
    float r00 = texture[idx00 + 0] / 255.0f;
    float r10 = texture[idx10 + 0] / 255.0f;
    float r01 = texture[idx01 + 0] / 255.0f;
    float r11 = texture[idx11 + 0] / 255.0f;
    color.x = (1.0f - wx) * (1.0f - wy) * r00 + wx * (1.0f - wy) * r10 +
              (1.0f - wx) * wy * r01 + wx * wy * r11;
    
    // Interpolate green channel
    float g00 = texture[idx00 + 1] / 255.0f;
    float g10 = texture[idx10 + 1] / 255.0f;
    float g01 = texture[idx01 + 1] / 255.0f;
    float g11 = texture[idx11 + 1] / 255.0f;
    color.y = (1.0f - wx) * (1.0f - wy) * g00 + wx * (1.0f - wy) * g10 +
              (1.0f - wx) * wy * g01 + wx * wy * g11;
    
    // Interpolate blue channel
    float b00 = texture[idx00 + 2] / 255.0f;
    float b10 = texture[idx10 + 2] / 255.0f;
    float b01 = texture[idx01 + 2] / 255.0f;
    float b11 = texture[idx11 + 2] / 255.0f;
    color.z = (1.0f - wx) * (1.0f - wy) * b00 + wx * (1.0f - wy) * b10 +
              (1.0f - wx) * wy * b01 + wx * wy * b11;
    
    return color;
}

// Background with procedural galaxy and stars (fallback if no texture)
__device__ Vec3 get_background_color(Vec3 dir, unsigned char* texture, int tex_width, int tex_height) {
    // If texture is available, use it
    if (texture != nullptr) {
        Vec3 tex_color = sample_background_texture(dir, texture, tex_width, tex_height);
        
        // Add some extra stars on top
        float star_density = 600.0f;
        float star = sinf(dir.x * star_density) * cosf(dir.y * star_density) * sinf(dir.z * star_density);
        star = star * star * star * star;
        star = fmaxf(0.0f, star - 0.996f) * 400.0f;
        
        tex_color.x += star * 0.3f;
        tex_color.y += star * 0.3f;
        tex_color.z += star * 0.3f;
        
        return tex_color;
    }
    
    // Fallback: procedural background
    // Stars - brighter and more visible
    float star_density = 500.0f;
    float star = sinf(dir.x * star_density) * cosf(dir.y * star_density) * sinf(dir.z * star_density);
    star = star * star * star * star;
    star = fmaxf(0.0f, star - 0.993f) * 300.0f;
    
    // Dark space background
    Vec3 bg = {0.01f + star, 0.01f + star, 0.02f + star};
    
    // Bright orange/red nebula
    float nebula_scale = 1.5f;
    float nebula = sinf(dir.x * nebula_scale) * cosf(dir.y * nebula_scale * 1.3f) * sinf(dir.z * nebula_scale * 0.7f);
    nebula = nebula * 0.5f + 0.5f;
    nebula = powf(nebula, 2.0f) * 0.25f;
    
    bg.x += nebula * 1.2f;  // Strong red
    bg.y += nebula * 0.4f;  // Medium orange
    bg.z += nebula * 0.1f;  // Minimal blue
    
    // Accretion disk glow in background (horizontal band)
    float disk_angle = fabsf(dir.y);
    if (disk_angle < 0.5f) {
        float disk_intensity = (0.5f - disk_angle) / 0.5f;
        
        // Multi-layer disk for more realism
        float inner_disk = powf(disk_intensity, 0.8f) * 1.2f;
        float outer_disk = powf(disk_intensity, 2.0f) * 0.8f;
        
        float total_intensity = inner_disk + outer_disk;
        
        // Hot plasma colors
        bg.x += total_intensity * 1.0f;   // Red
        bg.y += total_intensity * 0.6f;   // Orange/yellow
        bg.z += total_intensity * 0.1f;   // Slight blue
    }
    
    return bg;
}

// Ray tracing (grid removed)
__device__ Vec3 trace_ray(Vec3 origin, Vec3 direction, unsigned char* bg_texture, int tex_width, int tex_height) {
    Vec3 pos = origin;
    Vec3 vel = vec3_normalize(direction);
    
    // Check if ray starts inside event horizon
    float start_r = vec3_length(pos);
    if (start_r < SCHWARZSCHILD_RADIUS * 2.0f) {
        return get_background_color(direction, bg_texture, tex_width, tex_height);
    }
    
    for (int step = 0; step < MAX_STEPS; step++) {
        float r = vec3_length(pos);
        
        // Hit event horizon - return black
        if (r < SCHWARZSCHILD_RADIUS * 1.5f) {
            return {0.0f, 0.0f, 0.0f};
        }
        
        // Escaped to infinity
        if (r > 50.0f) {
            return get_background_color(vel, bg_texture, tex_width, tex_height);
        }
        
        // Apply gravitational deflection
        Vec3 accel = compute_acceleration(pos, vel);
        vel = vec3_add(vel, vec3_scale(accel, STEP_SIZE));
        vel = vec3_normalize(vel);
        pos = vec3_add(pos, vec3_scale(vel, STEP_SIZE));
    }
    
    // Max steps reached - show background
    return get_background_color(vel, bg_texture, tex_width, tex_height);
}

// CUDA kernel - renders to simple buffer
__global__ void render_kernel(unsigned char* image, int width, int height, 
                              float cam_x, float cam_y, float cam_z,
                              float right_x, float right_y, float right_z,
                              float up_x, float up_y, float up_z,
                              float forward_x, float forward_y, float forward_z,
                              unsigned char* bg_texture, int tex_width, int tex_height) {
    int px = blockIdx.x * blockDim.x + threadIdx.x;
    int py = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (px >= width || py >= height) return;
    
    Vec3 camera_pos = {cam_x, cam_y, cam_z};
    Vec3 right = {right_x, right_y, right_z};
    Vec3 up = {up_x, up_y, up_z};
    Vec3 forward = {forward_x, forward_y, forward_z};
    
    float u = (2.0f * px / width - 1.0f) * (float)width / height;
    float v = 1.0f - 2.0f * py / height;
    
    Vec3 ray_dir = vec3_normalize(vec3_add(
        vec3_add(vec3_scale(right, u * 0.8f), vec3_scale(up, v * 0.8f)),
        forward
    ));
    
    Vec3 color = trace_ray(camera_pos, ray_dir, bg_texture, tex_width, tex_height);
    
    // Tone mapping and gamma
    color.x = fminf(1.0f, color.x);
    color.y = fminf(1.0f, color.y);
    color.z = fminf(1.0f, color.z);
    
    color.x = powf(color.x, 1.0f / 2.2f);
    color.y = powf(color.y, 1.0f / 2.2f);
    color.z = powf(color.z, 1.0f / 2.2f);
    
    // Write RGB (flipped for OpenGL)
    int idx = ((height - 1 - py) * width + px) * 3;
    image[idx + 0] = (unsigned char)(color.x * 255.0f);
    image[idx + 1] = (unsigned char)(color.y * 255.0f);
    image[idx + 2] = (unsigned char)(color.z * 255.0f);
}

// Mouse callbacks
void mouse_button_callback(GLFWwindow* window, int button, int action, int mods) {
    if (button == GLFW_MOUSE_BUTTON_LEFT) {
        if (action == GLFW_PRESS) {
            g_mouse_pressed = true;
            glfwGetCursorPos(window, &g_last_x, &g_last_y);
        } else if (action == GLFW_RELEASE) {
            g_mouse_pressed = false;
        }
    }
}

void cursor_position_callback(GLFWwindow* window, double xpos, double ypos) {
    if (g_mouse_pressed) {
        double dx = xpos - g_last_x;
        double dy = ypos - g_last_y;
        
        g_camera.phi += dx * 0.005f;
        g_camera.theta += dy * 0.005f;
        
        if (g_camera.theta < 0.1f) g_camera.theta = 0.1f;
        if (g_camera.theta > 3.04f) g_camera.theta = 3.04f;
        
        // Pause auto-rotation when user interacts
        g_camera.rotation_speed = 0.0f;
        
        g_last_x = xpos;
        g_last_y = ypos;
    }
}

void scroll_callback(GLFWwindow* window, double xoffset, double yoffset) {
    g_camera.distance -= yoffset * 0.5f;
    if (g_camera.distance < 5.0f) g_camera.distance = 5.0f;
    if (g_camera.distance > 30.0f) g_camera.distance = 30.0f;
}

void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
        glfwSetWindowShouldClose(window, GLFW_TRUE);
    }
    if (key == GLFW_KEY_R && action == GLFW_PRESS) {
        g_camera = {15.0f, 1.2f, 0.0f, 0.15f};
    }
    if (key == GLFW_KEY_SPACE && action == GLFW_PRESS) {
        // Toggle auto-rotation
        if (g_camera.rotation_speed == 0.0f) {
            g_camera.rotation_speed = 0.4f;
        } else {
            g_camera.rotation_speed = 0.0f;
        }
    }
}

// Load image function (simple PPM loader)
unsigned char* load_ppm_image(const char* filename, int* width, int* height) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        printf("Warning: Could not open background image '%s'\n", filename);
        printf("Using procedural background instead.\n");
        return nullptr;
    }
    
    char buffer[16];
    int max_val;
    
    // Read PPM header
    if (!fgets(buffer, sizeof(buffer), fp)) {
        fclose(fp);
        return nullptr;
    }
    
    // Check format (P6 = binary PPM)
    if (buffer[0] != 'P' || buffer[1] != '6') {
        printf("Warning: Image must be in PPM P6 format\n");
        fclose(fp);
        return nullptr;
    }
    
    // Skip comments
    do {
        if (!fgets(buffer, sizeof(buffer), fp)) {
            fclose(fp);
            return nullptr;
        }
    } while (buffer[0] == '#');
    
    // Read dimensions
    sscanf(buffer, "%d %d", width, height);
    
    // Read max value
    if (!fgets(buffer, sizeof(buffer), fp)) {
        fclose(fp);
        return nullptr;
    }
    sscanf(buffer, "%d", &max_val);
    
    // Allocate and read image data
    size_t image_size = (*width) * (*height) * 3;
    unsigned char* data = (unsigned char*)malloc(image_size);
    
    if (fread(data, 1, image_size, fp) != image_size) {
        printf("Warning: Could not read full image\n");
        free(data);
        fclose(fp);
        return nullptr;
    }
    
    fclose(fp);
    printf("Loaded background image: %dx%d\n", *width, *height);
    return data;
}

int main() {
    printf("Interactive Schwarzschild Black Hole Simulator\n");
    printf("Controls:\n");
    printf("  - Left Click + Drag: Manual camera control (pauses auto-rotation)\n");
    printf("  - Mouse Wheel: Zoom in/out\n");
    printf("  - SPACE: Toggle auto-rotation on/off\n");
    printf("  - R: Reset camera\n");
    printf("  - ESC: Exit\n\n");
    
    // Load background texture
    int bg_width = 0, bg_height = 0;
    unsigned char* h_bg_texture = load_ppm_image("galaxy_background.ppm", &bg_width, &bg_height);
    
    // Upload background texture to GPU
    unsigned char* d_bg_texture = nullptr;
    if (h_bg_texture) {
        size_t bg_size = bg_width * bg_height * 3;
        cudaMalloc(&d_bg_texture, bg_size);
        cudaMemcpy(d_bg_texture, h_bg_texture, bg_size, cudaMemcpyHostToDevice);
        free(h_bg_texture);
    } else {
        printf("Note: Place a 'galaxy_background.ppm' file in the same directory for custom background\n");
        printf("You can convert any image to PPM using: convert image.jpg -resize 4096x4096! galaxy_background.ppm\n\n");
    }
    
    // Check CUDA
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        fprintf(stderr, "No CUDA devices found!\n");
        return -1;
    }
    
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("Using GPU: %s\n", prop.name);
    
    // Initialize GLFW
    if (!glfwInit()) {
        fprintf(stderr, "Failed to initialize GLFW\n");
        return -1;
    }
    
    // Create window
    GLFWwindow* window = glfwCreateWindow(WIDTH, HEIGHT, "Black Hole Simulator", NULL, NULL);
    if (!window) {
        fprintf(stderr, "Failed to create window\n");
        glfwTerminate();
        return -1;
    }
    
    glfwMakeContextCurrent(window);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetCursorPosCallback(window, cursor_position_callback);
    glfwSetScrollCallback(window, scroll_callback);
    glfwSetKeyCallback(window, key_callback);
    glfwSwapInterval(0); // Disable V-sync for higher FPS
    
    // Initialize GLEW
    if (glewInit() != GLEW_OK) {
        fprintf(stderr, "Failed to initialize GLEW\n");
        return -1;
    }
    
    // Create OpenGL texture (no CUDA interop)
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    // Allocate buffers
    size_t image_size = WIDTH * HEIGHT * 3;
    unsigned char* h_image = (unsigned char*)malloc(image_size);
    unsigned char* d_image;
    cudaMalloc(&d_image, image_size);
    
    // CUDA kernel config
    dim3 block_size(16, 16);
    dim3 grid_size((WIDTH + block_size.x - 1) / block_size.x,
                   (HEIGHT + block_size.y - 1) / block_size.y);
    
    printf("Rendering at %dx%d...\n\n", WIDTH, HEIGHT);
    
    int frame_count = 0;
    double last_time = glfwGetTime();
    double fps_time = last_time;
    int fps_frames = 0;
    
    // Main loop
    while (!glfwWindowShouldClose(window)) {
        // Calculate delta time for smooth rotation
        double current_time = glfwGetTime();
        double delta_time = current_time - last_time;
        last_time = current_time;
        
        // Auto-rotate camera with frame-independent speed
        g_camera.phi += g_camera.rotation_speed * delta_time;
        
        // Calculate camera
        float cam_x = g_camera.distance * sinf(g_camera.theta) * cosf(g_camera.phi);
        float cam_y = g_camera.distance * cosf(g_camera.theta);
        float cam_z = g_camera.distance * sinf(g_camera.theta) * sinf(g_camera.phi);
        
        float forward_x = -cam_x / g_camera.distance;
        float forward_y = -cam_y / g_camera.distance;
        float forward_z = -cam_z / g_camera.distance;
        
        float right_x = -sinf(g_camera.phi);
        float right_y = 0.0f;
        float right_z = cosf(g_camera.phi);
        
        float up_x = -cosf(g_camera.theta) * cosf(g_camera.phi);
        float up_y = sinf(g_camera.theta);
        float up_z = -cosf(g_camera.theta) * sinf(g_camera.phi);
        
        // Render with CUDA
        render_kernel<<<grid_size, block_size>>>(
            d_image, WIDTH, HEIGHT,
            cam_x, cam_y, cam_z,
            right_x, right_y, right_z,
            up_x, up_y, up_z,
            forward_x, forward_y, forward_z,
            d_bg_texture, bg_width, bg_height
        );
        
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            printf("CUDA error: %s\n", cudaGetErrorString(err));
            break;
        }
        
        cudaDeviceSynchronize();
        
        // Copy to host
        cudaMemcpy(h_image, d_image, image_size, cudaMemcpyDeviceToHost);
        
        // Upload to OpenGL
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, WIDTH, HEIGHT, 0, GL_RGB, GL_UNSIGNED_BYTE, h_image);
        
        // Render quad
        glClear(GL_COLOR_BUFFER_BIT);
        glEnable(GL_TEXTURE_2D);
        
        glBegin(GL_QUADS);
        glTexCoord2f(0, 0); glVertex2f(-1, -1);
        glTexCoord2f(1, 0); glVertex2f(1, -1);
        glTexCoord2f(1, 1); glVertex2f(1, 1);
        glTexCoord2f(0, 1); glVertex2f(-1, 1);
        glEnd();
        
        glfwSwapBuffers(window);
        glfwPollEvents();
        
        frame_count++;
        fps_frames++;
        
        // Display FPS every second
        if (current_time - fps_time >= 1.0) {
            double fps = fps_frames / (current_time - fps_time);
            printf("FPS: %.1f | Frames: %d\r", fps, frame_count);
            fflush(stdout);
            fps_frames = 0;
            fps_time = current_time;
        }
    }
    
    printf("\nExiting...\n");
    
    // Cleanup
    if (d_bg_texture) cudaFree(d_bg_texture);
    cudaFree(d_image);
    free(h_image);
    glDeleteTextures(1, &texture);
    glfwDestroyWindow(window);
    glfwTerminate();
    
    return 0;
}

