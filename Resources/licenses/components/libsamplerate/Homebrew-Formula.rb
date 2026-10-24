class Libsamplerate < Formula
  desc "Library for sample rate conversion of audio data"
  homepage "https://github.com/libsndfile/libsamplerate"
  url "https://github.com/libsndfile/libsamplerate/archive/refs/tags/0.2.2.tar.gz"
  sha256 "16e881487f184250deb4fcb60432d7556ab12cb58caea71ef23960aec6c0405a"
  license "BSD-2-Clause"

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build

  def install
    args = ["-DLIBSAMPLERATE_EXAMPLES=OFF"]

    system "cmake", "-S", ".", "-B", "build_shared", "-DBUILD_SHARED_LIBS=ON", *args, *std_cmake_args
    system "cmake", "--build", "build_shared"
    system "cmake", "--install", "build_shared"

    system "cmake", "-S", ".", "-B", "build_static", "-DBUILD_SHARED_LIBS=OFF", *args, *std_cmake_args
    system "cmake", "--build", "build_static"
    lib.install "build_static/src/libsamplerate.a"
  end

  test do
    (testpath/"test.c").write <<~C
      #include <assert.h>
      #include <samplerate.h>
      int main() {
        SRC_DATA src_data;
        float input[] = {0.1, 0.9, 0.7, 0.4} ;
        float output[2] ;
        src_data.data_in = input ;
        src_data.data_out = output ;
        src_data.input_frames = 4 ;
        src_data.output_frames = 2 ;
        src_data.src_ratio = 0.5 ;
        int res = src_simple (&src_data, 2, 1) ;
        assert(res == 0);
        return 0;
      }
    C
    system ENV.cc, "test.c", "-I#{include}", "-L#{opt_lib}", "-lsamplerate", "-o", "test"
    system "./test"
  end
end
