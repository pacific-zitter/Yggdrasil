using BinaryBuilder

name = "CompilerSupportLibraries"
bb_version = BinaryBuilder.get_bb_version()
version = VersionNumber(bb_version.major, bb_version.minor, bb_version.patch)

# We are going to need to extract the latest libstdc++ and libgomp from BB
# So let's grab them into tarballs by using preferred_gcc_version:
extraction_script = raw"""
mkdir -p ${libdir}
for d in /opt/${target}/${target}/lib*; do
    # Copy all the libstdc++ and libgomp files:
    cp -av ${d}/libstdc++*.${dlext}* ${libdir} || true
    cp -av ${d}/libgomp*.${dlext}* ${libdir} || true

    # Don't copy `.a` or `.py` files.  >:[
    rm -f ${libdir}/*.a
    rm -f ${libdir}/*.py
done
"""

extraction_platforms = supported_platforms()
extraction_products = [
    LibraryProduct("libstdc++", :libstdcxx),
    LibraryProduct("libgomp", :libgomp),
]
build_info = autobuild(joinpath(@__DIR__, "build", "extraction"),
    "LatestLibraries",
    version,
    FileSource[],
    extraction_script,
    extraction_platforms,
    extraction_products,
    Dependency[];
    skip_audit=true,
    preferred_gcc_version=v"100",
    verbose="--verbose" in ARGS,
    debug="--debug" in ARGS,
)



## Now that we've got those tarballs, we're going to use them as sources to overwrite
## the libstdc++ and libgomp that we would otherwise get from our compiler shards:

script = raw"""
mkdir -p ${libdir}

# copy out all the libraries we can find
for d in /opt/${target}/${target}/lib*; do
    cp -av ${d}/*.${dlext}* ${libdir} || true

    # Delete .a and .py files
    rm -f ${libdir}/*.a ${libdir}/*.py
done

# change permissions so that rpath succeeds
for l in ${libdir}/*; do
    chmod 0755 "${l}"
done

# libgcc_s.1.dylib receives special treatment for now
if [[ ${target} == *apple* ]]; then
    install_name_tool -id @rpath/libgcc_s.1.dylib ${libdir}/libgcc_s.1.dylib
fi

# Install license (we license these all as GPL3, since they're from GCC)
install_license /usr/share/licenses/GPL3
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = expand_gfortran_versions(supported_platforms())

# The products that we will ensure are always built
products = [
    LibraryProduct(["libgcc_s", "libgcc_s_sjlj", "libgcc_s_seh"], :libgcc_s),
    LibraryProduct("libstdc++", :libstdcxx),
    LibraryProduct("libgfortran", :libgfortran),
    LibraryProduct("libgomp", :libgomp),
]

# Build the tarballs, and possibly a `build.jl` as well.
for platform in platforms
    # Find the corresponding source for this platform
    tarball_path, tarball_hash = build_info[BinaryBuilder.abi_agnostic(platform)][1:2]
    sources = [
        FileSource(tarball_path, tarball_hash),
    ]
    build_tarballs(ARGS, name, version, sources, script, [platform], products, [])
end
